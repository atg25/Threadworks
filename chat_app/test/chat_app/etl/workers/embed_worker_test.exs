defmodule ChatApp.ETL.Workers.EmbedWorkerTest do
  use ChatApp.DataCase, async: false

  alias ChatApp.ETL.Workers.EmbedWorker
  alias ChatApp.ETL.Embedder
  alias ChatApp.AI.VectorCodec
  alias ChatApp.ETL.Deduplicator
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.Repo

  import Ecto.Query

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp embeddings_fixture_path do
    Path.join([File.cwd!(), "test", "support", "http_mocks", "openai_embeddings_response.json"])
  end

  defp embeddings_fixture, do: File.read!(embeddings_fixture_path())

  defp embeddings_fixture_with_count(count) do
    full = Jason.decode!(embeddings_fixture())
    trimmed_data = Enum.take(full["data"], count)
    Jason.encode!(Map.put(full, "data", trimmed_data))
  end

  defp valid_item_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        source: "ebay",
        source_id: "v1|embed|#{System.unique_integer([:positive])}",
        title: "Vintage Levi's 501",
        brand: "Levi's",
        price: Decimal.new("24.99"),
        url: "https://ebay.com/item/#{System.unique_integer([:positive])}",
        condition_normalized: "good",
        last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      overrides
    )
  end

  defp build_and_insert_items(n) do
    items =
      Enum.map(1..n, fn i ->
        valid_item_attrs(%{
          source_id: "v1|embed|#{System.unique_integer([:positive])}",
          title: "Item #{i}"
        })
      end)

    {:ok, inserted} = Deduplicator.upsert_all(items)
    inserted
  end

  defp perform(item_ids) do
    EmbedWorker.perform(%Oban.Job{args: %{"item_ids" => item_ids}})
  end

  defp stub_embeddings(bypass, body \\ nil) do
    response_body = body || embeddings_fixture()

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, response_body)
    end)
  end

  defp setup_bypass do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :openai_embeddings_url, "http://localhost:#{bypass.port}/v1/embeddings")
    bypass
  end

  # ---------------------------------------------------------------------------
  # Integration Test 1
  # perform/1 calls OpenAI embeddings API exactly once for batch of 20 items
  # ---------------------------------------------------------------------------

  test "perform/1 calls OpenAI embeddings API exactly once for batch of 20 items" do
    bypass = setup_bypass()
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      Agent.update(counter, &(&1 + 1))

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, embeddings_fixture())
    end)

    items = build_and_insert_items(20)
    ids = Enum.map(items, & &1.id)

    perform(ids)

    assert Agent.get(counter, & &1) == 1

  end

  # ---------------------------------------------------------------------------
  # Integration Test 2
  # perform/1 request body contains dimensions: 512
  # ---------------------------------------------------------------------------

  test "perform/1 request body contains dimensions: 512" do
    bypass = setup_bypass()
    {:ok, captured} = Agent.start_link(fn -> nil end)

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      Agent.update(captured, fn _ -> decoded end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, embeddings_fixture())
    end)

    items = build_and_insert_items(20)
    ids = Enum.map(items, & &1.id)

    perform(ids)

    body = Agent.get(captured, & &1)
    assert body["dimensions"] == 512, "expected dimensions: 512 in request body, got: #{inspect(body["dimensions"])}"
    assert body["model"] == "text-embedding-3-small"
    assert length(body["input"]) == 20

  end

  # ---------------------------------------------------------------------------
  # Integration Test 3
  # perform/1 stores 2048-byte binary embedding on each item
  # ---------------------------------------------------------------------------

  test "perform/1 stores 2048-byte binary embedding on each item" do
    bypass = setup_bypass()
    stub_embeddings(bypass)

    items = build_and_insert_items(20)
    ids = Enum.map(items, & &1.id)

    perform(ids)

    stored = Repo.all(from i in ClothingItem, where: i.id in ^ids)

    assert Enum.all?(stored, fn i ->
             is_binary(i.embedding) and byte_size(i.embedding) == 2048
           end),
           "expected all items to have 2048-byte binary embeddings"

  end

  # ---------------------------------------------------------------------------
  # Integration Test 4
  # perform/1 upserts all items into clothing_vec
  # ---------------------------------------------------------------------------

  test "perform/1 upserts all items into clothing_vec" do
    bypass = setup_bypass()
    stub_embeddings(bypass)

    items = build_and_insert_items(20)
    ids = Enum.map(items, & &1.id)

    perform(ids)

    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM clothing_vec WHERE rowid IN (#{Enum.join(ids, ",")})")
    assert count == 20, "expected 20 rows in clothing_vec, got #{count}"

  end

  # ---------------------------------------------------------------------------
  # Integration Test 5
  # perform/1 updates FTS5 index: items findable by title keyword search
  # ---------------------------------------------------------------------------

  test "perform/1 updates FTS5 index: items findable by title keyword search" do
    bypass = setup_bypass()
    stub_embeddings(bypass)

    [item] =
      build_and_insert_items(1)
      |> tap(fn [i] ->
        Repo.update!(Ecto.Changeset.change(i, title: "vintage windbreaker"))
      end)

    # Re-fetch to get the updated title
    item = Repo.get!(ClothingItem, item.id)

    perform([item.id])

    %{rows: rows} =
      Repo.query!("SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH ?", ["windbreaker"])

    rowids = List.flatten(rows)
    assert item.id in rowids, "expected item id #{item.id} in FTS results, got: #{inspect(rowids)}"

  end

  # ---------------------------------------------------------------------------
  # Integration Test 6
  # perform/1 returns {:error, :embedding_count_mismatch} when OpenAI returns
  # fewer embeddings than items
  # ---------------------------------------------------------------------------

  test "perform/1 returns {:error, :embedding_count_mismatch} when OpenAI returns fewer embeddings than items" do
    bypass = setup_bypass()

    # Return only 18 embeddings for 20 items
    stub_embeddings(bypass, embeddings_fixture_with_count(18))

    items = build_and_insert_items(20)
    ids = Enum.map(items, & &1.id)

    result = perform(ids)

    assert result == {:error, :embedding_count_mismatch},
           "expected {:error, :embedding_count_mismatch}, got: #{inspect(result)}"

  end

  # ---------------------------------------------------------------------------
  # Integration Test 7
  # perform/1 skips item_ids not found in DB without crashing
  # ---------------------------------------------------------------------------

  test "perform/1 skips item_ids not found in DB without crashing" do
    bypass = setup_bypass()
    stub_embeddings(bypass)

    items = build_and_insert_items(20)
    valid_ids = Enum.map(items, & &1.id)

    # Include a stale id that does not exist in the DB
    stale_id = 999_999_999
    ids_with_stale = valid_ids ++ [stale_id]

    result = perform(ids_with_stale)

    assert result == :ok, "expected :ok when stale id included, got: #{inspect(result)}"

  end

  # ---------------------------------------------------------------------------
  # Unit Test 8 — Embedder.embed_batch/1
  # embed_batch/1 returns {:ok, list_of_float_lists}
  # ---------------------------------------------------------------------------

  test "embed_batch/1 returns {:ok, list_of_float_lists}" do
    bypass = setup_bypass()

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, embeddings_fixture())
    end)

    texts = Enum.map(1..20, fn i -> "text #{i}" end)
    result = Embedder.embed_batch(texts)

    assert {:ok, embeddings} = result
    assert length(embeddings) == 20

    assert Enum.all?(embeddings, fn emb ->
             is_list(emb) and length(emb) == 512 and Enum.all?(emb, &is_float/1)
           end),
           "expected each embedding to be a list of 512 floats"

  end

  # ---------------------------------------------------------------------------
  # Unit Test 9 — Embedder.embed_batch/1
  # embed_batch/1 sends dimensions: 512 in request body
  # ---------------------------------------------------------------------------

  test "embed_batch/1 sends dimensions: 512 in request body" do
    bypass = setup_bypass()
    {:ok, captured} = Agent.start_link(fn -> nil end)

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(captured, fn _ -> Jason.decode!(body) end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, embeddings_fixture())
    end)

    Embedder.embed_batch(["hello"])

    body = Agent.get(captured, & &1)
    assert body["dimensions"] == 512, "expected dimensions: 512 in request body, got: #{inspect(body["dimensions"])}"

  end

  # ---------------------------------------------------------------------------
  # Unit Test 10 — VectorCodec dimension guard
  # VectorCodec.encode/1 raises ArgumentError for 1536-element list
  # ---------------------------------------------------------------------------

  test "VectorCodec.encode/1 raises ArgumentError for 1536-element list" do
    assert_raise ArgumentError, ~r/requires exactly 512 elements, got 1536/, fn ->
      VectorCodec.encode(List.duplicate(0.1, 1536))
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrency Test 11
  # two concurrent EmbedWorker jobs: no SQLite busy_timeout errors
  # ---------------------------------------------------------------------------

  test "two concurrent EmbedWorker jobs: no SQLite busy_timeout errors" do
    bypass = setup_bypass()

    # Both requests share the same 20-embedding fixture; stub handles concurrency
    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, embeddings_fixture())
    end)

    # Insert 40 items split into two groups of 20
    group_a = build_and_insert_items(20)
    group_b = build_and_insert_items(20)
    ids_a = Enum.map(group_a, & &1.id)
    ids_b = Enum.map(group_b, & &1.id)
    all_ids = ids_a ++ ids_b

    results =
      Task.async_stream(
        [ids_a, ids_b],
        fn ids -> perform(ids) end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.to_list()

    for {:ok, result} <- results do
      refute match?({:exit, _}, result), "worker task exited unexpectedly: #{inspect(result)}"

      assert result == :ok or match?({:error, _}, result),
             "unexpected result: #{inspect(result)}"
    end

    # Both tasks must have returned :ok
    assert Enum.all?(results, fn {:ok, r} -> r == :ok end),
           "expected both concurrent jobs to return :ok, got: #{inspect(results)}"

    # All 40 items must have non-nil embeddings
    stored = Repo.all(from i in ClothingItem, where: i.id in ^all_ids)

    assert Enum.all?(stored, fn i -> not is_nil(i.embedding) end),
           "expected all 40 items to have embeddings after concurrent jobs"

    # No SQLITE_BUSY errors should have escaped — the Task results above verify this,
    # but also check that no items were left un-embedded
    assert length(stored) == 40

    # Verify no task exited with Exqlite.Error containing SQLITE_BUSY
    for {:ok, result} <- results do
      refute match?({:error, %_{message: msg}} when is_binary(msg), result) and
               String.contains?(inspect(result), "SQLITE_BUSY"),
             "SQLite busy_timeout error detected: #{inspect(result)}"
    end

  end
end
