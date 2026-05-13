defmodule ChatApp.Search.HybridEngineIntegrationTest do
  use ChatApp.DataCase, async: false

  @moduletag :integration

  alias ChatApp.Search.HybridEngine
  alias ChatApp.Search.VectorStore
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  @embeddings Code.eval_file(Path.join([__DIR__, "../../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a

  @openai_url Application.compile_env(
                :chat_app,
                :openai_embeddings_url,
                "https://api.openai.com/v1/embeddings"
              )

  # Stubs Bypass to return fixture_a as a valid 512-dim embedding response.
  defp stub_embedder(bypass, vec \\ nil) do
    embedding = vec || @fixture_a

    body =
      Jason.encode!(%{
        "object" => "list",
        "model" => "text-embedding-3-small",
        "data" => [%{"object" => "embedding", "index" => 0, "embedding" => embedding}]
      })

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  defp stub_embedder_error(bypass, status \\ 500) do
    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(status, Jason.encode!(%{"error" => %{"message" => "api_down"}}))
    end)
  end

  defp open_bypass do
    bypass = Bypass.open()
    original = Application.get_env(:chat_app, :openai_embeddings_url)

    Application.put_env(
      :chat_app,
      :openai_embeddings_url,
      "http://localhost:#{bypass.port}/v1/embeddings"
    )

    on_exit(fn -> Application.put_env(:chat_app, :openai_embeddings_url, original) end)
    bypass
  end

  defp insert_item(attrs) do
    {:ok, item} =
      Repo.insert(Item.changeset(%Item{}, Map.merge(%{source: "ebay"}, attrs)))

    item
  end

  # ---------------------------------------------------------------------------
  # I-01 — search/2 returns {:ok, []} when DB has no items
  # ---------------------------------------------------------------------------

  test "I-01: search/2 returns {:ok, []} when DB has no items" do
    bypass = open_bypass()
    stub_embedder(bypass)

    assert {:ok, []} = HybridEngine.search("vintage jacket")
  end

  # ---------------------------------------------------------------------------
  # I-02 — search/2 returns {:ok, []} for empty query without calling Embedder
  # ---------------------------------------------------------------------------

  test "I-02: search/2 returns {:ok, []} for empty query without calling Embedder" do
    # Bypass is closed — any HTTP request would fail, proving Embedder was not called
    bypass = open_bypass()

    Bypass.down(bypass)
    on_exit(fn -> Bypass.up(bypass) end)

    assert {:ok, []} = HybridEngine.search("")
  end

  # ---------------------------------------------------------------------------
  # I-03 — search/2 propagates Embedder error as {:error, reason}
  # ---------------------------------------------------------------------------

  test "I-03: search/2 propagates Embedder error as {:error, reason}" do
    bypass = open_bypass()
    stub_embedder_error(bypass, 500)

    item =
      insert_item(%{title: "Vintage Levi Denim Jacket", price: "25.00", url: "http://e.com/i03"})

    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)

    result = HybridEngine.search("jacket")

    assert match?({:error, _}, result),
           "expected {:error, _} when Embedder fails, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-04 — search/2 returns %ClothingItem{} structs with positive :rrf_score
  # ---------------------------------------------------------------------------

  test "I-04: search/2 returns %ClothingItem{} structs with positive :rrf_score float" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item_a =
      insert_item(%{
        title: "Vintage Levi Denim Jacket Secondhand",
        price: "25.00",
        url: "http://e.com/i04a"
      })

    item_b =
      insert_item(%{
        title: "Pink Silk Evening Gown Formal Wear",
        price: "80.00",
        url: "http://e.com/i04b",
        source: "depop"
      })

    :ok = VectorStore.upsert(item_a.id, @fixture_a)
    :ok = VectorStore.upsert(item_b.id, @fixture_a)
    :ok = FTS5Index.upsert(item_a.id)
    :ok = FTS5Index.upsert(item_b.id)

    assert {:ok, items} = HybridEngine.search("vintage jacket")

    assert length(items) >= 1,
           "expected at least 1 result, got: #{inspect(items)}"

    Enum.each(items, fn item ->
      assert is_struct(item, ChatApp.Clothing.Item),
             "expected %ClothingItem{} struct, got: #{inspect(item)}"

      assert item.rrf_score > 0,
             "expected rrf_score > 0, got: #{inspect(item.rrf_score)}"
    end)
  end

  # ---------------------------------------------------------------------------
  # I-05 (Acceptance criterion) — Item A ranks before Items B and C
  # ---------------------------------------------------------------------------

  test "I-05: Item A ranks before Items B and C for 'vintage levi denim jacket'" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item_a =
      insert_item(%{
        title: "Vintage Levi Denim Jacket Secondhand",
        price: "25.00",
        url: "http://e.com/i05a"
      })

    item_b =
      insert_item(%{
        title: "Pink Silk Evening Gown Formal Wear",
        price: "80.00",
        url: "http://e.com/i05b",
        source: "depop"
      })

    item_c =
      insert_item(%{
        title: "Denim Jacket Indigo Blue Worn Preloved",
        price: "35.00",
        url: "http://e.com/i05c"
      })

    :ok = VectorStore.upsert(item_a.id, @fixture_a)
    :ok = VectorStore.upsert(item_b.id, @fixture_a)
    :ok = VectorStore.upsert(item_c.id, @fixture_a)
    :ok = FTS5Index.upsert(item_a.id)
    :ok = FTS5Index.upsert(item_b.id)
    :ok = FTS5Index.upsert(item_c.id)

    assert {:ok, [first | _]} = HybridEngine.search("vintage levi denim jacket")

    assert first.id == item_a.id,
           "expected item_a (id=#{item_a.id}) as first result, got id=#{first.id}"
  end

  # ---------------------------------------------------------------------------
  # I-06 — search/2 completes within 1 second (no hanging Task.await)
  # ---------------------------------------------------------------------------

  @tag timeout: 1_000
  test "I-06: search/2 completes without hanging" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item = insert_item(%{title: "Leather Jacket", price: "40.00", url: "http://e.com/i06"})
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)

    assert {:ok, _items} = HybridEngine.search("jacket")
  end

  # ---------------------------------------------------------------------------
  # I-07 — search/2 handles a Task exception from VectorStore without crashing the caller
  #
  # This test corrupts the clothing_vec virtual table to force VectorStore to raise,
  # then verifies the HybridEngine returns {:error, _} instead of crashing the process.
  # ---------------------------------------------------------------------------

  test "I-07: Task exception from VectorStore is caught and returned as {:error, _}" do
    bypass = open_bypass()
    stub_embedder(bypass)

    # Drop clothing_vec to force a runtime error in the VectorStore Task
    Repo.query!("DROP TABLE IF EXISTS clothing_vec", [])

    result = HybridEngine.search("jacket")

    Repo.query!(
      "CREATE VIRTUAL TABLE IF NOT EXISTS clothing_vec USING vec0(embedding float[512])",
      []
    )

    assert match?({:error, _}, result),
           "expected {:error, _} when VectorStore Task raises, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-08 — Items deleted between search and DB fetch are silently dropped
  # ---------------------------------------------------------------------------

  test "I-08: items deleted between search and DB fetch are silently dropped" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item_a =
      insert_item(%{title: "Vintage Denim Jacket", price: "30.00", url: "http://e.com/i08a"})

    item_b =
      insert_item(%{
        title: "Vintage Denim Jacket Similar",
        price: "32.00",
        url: "http://e.com/i08b"
      })

    :ok = VectorStore.upsert(item_a.id, @fixture_a)
    :ok = VectorStore.upsert(item_b.id, @fixture_a)
    :ok = FTS5Index.upsert(item_a.id)
    :ok = FTS5Index.upsert(item_b.id)

    # Delete item_b's clothing_items row — leave vec and FTS entries orphaned
    Repo.delete!(item_b)

    assert {:ok, items} = HybridEngine.search("vintage denim jacket")

    ids = Enum.map(items, & &1.id)

    assert item_a.id in ids,
           "expected item_a in results, got ids: #{inspect(ids)}"

    refute item_b.id in ids,
           "expected deleted item_b NOT in results, got ids: #{inspect(ids)}"
  end
end
