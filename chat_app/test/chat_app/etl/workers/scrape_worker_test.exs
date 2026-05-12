defmodule ChatApp.ETL.Workers.ScrapeWorkerTest do
  use ChatApp.DataCase, async: false

  alias ChatApp.ETL.Workers.ScrapeWorker
  alias ChatApp.ETL.Sources.Ebay.TokenCache
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo

  import Ecto.Query

  @ebay_search_path "/buy/browse/v1/item_summary/search"

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ebay_search_fixture do
    Path.join([File.cwd!(), "test", "support", "http_mocks", "ebay_search_response.json"])
    |> File.read!()
  end

  defp far_future_datetime do
    DateTime.add(DateTime.utc_now(), 7200, :second)
  end

  defp seed_valid_token(token \\ "valid_token") do
    TokenCache.put(token, far_future_datetime())
  end

  defp setup_ebay_bypass do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")
    TokenCache.clear()
    bypass
  end

  # Stub eBay to return `count` items synthesized from the fixture items list.
  # Pulls real items from the fixture to ensure all required fields are present.
  defp stub_ebay_items(bypass, count) do
    fixture = Jason.decode!(ebay_search_fixture())
    base_items = fixture["itemSummaries"]

    items =
      Stream.cycle(base_items)
      |> Stream.with_index()
      |> Enum.take(count)
      |> Enum.map(fn {item, idx} ->
        Map.put(item, "itemId", "v1|synthetic|#{idx}")
      end)

    body = Jason.encode!(%{"total" => count, "itemSummaries" => items})

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  defp perform_ebay(query \\ "vintage levi") do
    ScrapeWorker.perform(%Oban.Job{args: %{"source" => "ebay", "query" => query}})
  end

  # ---------------------------------------------------------------------------
  # E2E Test 1
  # perform/1 eBay source: ≥ 20 items persisted with non-null required fields
  # ---------------------------------------------------------------------------

  test "perform/1 eBay source: ≥ 20 items persisted with non-null required fields" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    perform_ebay()

    count = Repo.aggregate(from(i in ClothingItem, where: i.source == "ebay"), :count)
    assert count >= 20

    items = Repo.all(from(i in ClothingItem, where: i.source == "ebay"))

    for item <- items do
      refute is_nil(item.title), "title must not be nil"
      refute is_nil(item.price), "price must not be nil"
      refute is_nil(item.source_id), "source_id must not be nil"
      refute is_nil(item.url), "url must not be nil"
    end
  end

  # ---------------------------------------------------------------------------
  # E2E Test 2
  # perform/1 25 items → exactly 2 EmbedWorker jobs enqueued (chunks: 20 + 5)
  # ---------------------------------------------------------------------------

  test "perform/1 25 items → exactly 2 EmbedWorker jobs enqueued (chunks: 20 + 5)" do
    bypass = setup_ebay_bypass()
    seed_valid_token()
    stub_ebay_items(bypass, 25)

    Oban.Testing.with_testing_mode(:manual, fn ->
      perform_ebay()

      count =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.EmbedWorker"),
          :count
        )

      assert count == 2
    end)
  end

  # ---------------------------------------------------------------------------
  # E2E Test 3
  # perform/1 EmbedWorker job args: first job has 20 item_ids, second has 5
  # ---------------------------------------------------------------------------

  test "perform/1 EmbedWorker job args: first job has 20 item_ids, second has 5" do
    bypass = setup_ebay_bypass()
    seed_valid_token()
    stub_ebay_items(bypass, 25)

    Oban.Testing.with_testing_mode(:manual, fn ->
      perform_ebay()

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "ChatApp.ETL.Workers.EmbedWorker",
            order_by: [asc: j.id]
          )
        )

      assert length(jobs) == 2
      assert length(hd(jobs).args["item_ids"]) == 20
      assert length(List.last(jobs).args["item_ids"]) == 5
    end)
  end

  # ---------------------------------------------------------------------------
  # E2E Test 4
  # perform/1 EmbedWorker item_ids are DB integer ids, not source_id strings
  # ---------------------------------------------------------------------------

  test "perform/1 EmbedWorker item_ids are DB integer ids, not source_id strings" do
    bypass = setup_ebay_bypass()
    seed_valid_token()
    stub_ebay_items(bypass, 25)

    Oban.Testing.with_testing_mode(:manual, fn ->
      perform_ebay()

      [job | _] =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "ChatApp.ETL.Workers.EmbedWorker",
            order_by: [asc: j.id]
          )
        )

      assert Enum.all?(job.args["item_ids"], &is_integer/1),
             "item_ids must be DB integer ids, not source_id strings"
    end)
  end

  # ---------------------------------------------------------------------------
  # Integration Test 5
  # perform/1 returns :ok on success
  # ---------------------------------------------------------------------------

  test "perform/1 returns :ok on success" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    assert perform_ebay() == :ok
  end

  # ---------------------------------------------------------------------------
  # Integration Test 6
  # perform/1 eBay source HTTP failure: returns {:error, reason}, no crash
  # ---------------------------------------------------------------------------

  test "perform/1 eBay source HTTP failure: returns {:error, reason}, no crash" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      Plug.Conn.resp(conn, 500, "Internal Server Error")
    end)

    result = perform_ebay()
    assert match?({:error, _}, result), "expected {:error, _}, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # Integration Test 7
  # perform/1 items tagged with correct source after persist
  # ---------------------------------------------------------------------------

  test "perform/1 items tagged with correct source after persist" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    perform_ebay()

    items = Repo.all(ClothingItem)
    assert length(items) > 0

    for item <- items do
      assert item.source == "ebay", "expected source 'ebay', got #{inspect(item.source)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Integration Test 8
  # max_attempts is 3
  # ---------------------------------------------------------------------------

  test "max_attempts is 3" do
    opts = ScrapeWorker.__opts__()
    assert opts[:max_attempts] == 3
  end

  # ---------------------------------------------------------------------------
  # Concurrency Test 9
  # two concurrent perform/1 calls same source+query: no unique constraint errors
  # ---------------------------------------------------------------------------

  test "two concurrent perform/1 calls same source+query: no unique constraint errors" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    results =
      Task.async_stream(
        [1, 2],
        fn _ ->
          perform_ebay()
        end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.to_list()

    for {:ok, result} <- results do
      assert match?(:ok, result) or match?({:error, _}, result),
             "expected :ok or {:error, _}, got #{inspect(result)}"
    end

    refute Enum.any?(results, fn
             {:exit, %Ecto.ConstraintError{}} -> true
             _ -> false
           end),
           "Ecto.ConstraintError raised — Deduplicator on_conflict not wired"
  end

  # ---------------------------------------------------------------------------
  # Concurrency Test 10
  # two concurrent perform/1 calls same source+query: price_history count == 2N
  # ---------------------------------------------------------------------------

  test "two concurrent perform/1 calls same source+query: price_history count == 2N" do
    bypass = setup_ebay_bypass()
    seed_valid_token()

    fixture_items = Jason.decode!(ebay_search_fixture())["itemSummaries"]
    n = length(fixture_items)

    Bypass.stub(bypass, "GET", @ebay_search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    Task.async_stream(
      [1, 2],
      fn _ -> perform_ebay() end,
      max_concurrency: 2,
      timeout: 30_000
    )
    |> Enum.to_list()

    ph_count = Repo.aggregate(PriceHistory, :count)

    assert ph_count == 2 * n,
           "expected price_history count #{2 * n}, got #{ph_count} — one worker may have skipped writing history"
  end
end
