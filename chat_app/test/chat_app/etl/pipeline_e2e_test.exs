defmodule ChatApp.ETL.PipelineE2ETest do
  use ChatApp.DataCase, async: false

  alias ChatApp.ETL.Workers.ScrapeWorker
  alias ChatApp.ETL.Sources.Ebay.TokenCache
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo

  import Ecto.Query

  # ---------------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------------

  defp ebay_fixture, do: File.read!(fixture_path("ebay_search_response.json"))
  defp depop_fixture, do: File.read!(fixture_path("depop_search_response.json"))
  defp poshmark_fixture, do: File.read!(fixture_path("poshmark_search.html"))
  defp openai_fixture, do: File.read!(fixture_path("openai_embeddings_response.json"))

  defp fixture_path(name),
    do: Path.join([File.cwd!(), "test", "support", "http_mocks", name])

  defp far_future, do: DateTime.add(DateTime.utc_now(), 7200, :second)

  defp openai_fixture_for_count(count) do
    full = Jason.decode!(openai_fixture())
    trimmed = Enum.take(full["data"], count)
    Jason.encode!(Map.put(full, "data", trimmed))
  end

  # ---------------------------------------------------------------------------
  # Bypass setup helpers
  # ---------------------------------------------------------------------------

  defp open_ebay_bypass(ebay_response \\ nil) do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")
    TokenCache.clear()
    TokenCache.put("valid_token", far_future())

    body = ebay_response || stub_ebay_body(20)

    Bypass.stub(bypass, "GET", "/buy/browse/v1/item_summary/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)

    bypass
  end

  defp open_ebay_bypass_500 do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")
    TokenCache.clear()
    TokenCache.put("valid_token", far_future())

    Bypass.stub(bypass, "GET", "/buy/browse/v1/item_summary/search", fn conn ->
      Plug.Conn.resp(conn, 500, "Internal Server Error")
    end)

    bypass
  end

  defp open_depop_bypass do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{bypass.port}")

    Bypass.stub(bypass, "GET", "/api/v3/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, depop_fixture())
    end)

    bypass
  end

  defp open_poshmark_bypass do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :poshmark_base_url, "http://localhost:#{bypass.port}")

    Bypass.stub(bypass, "GET", "/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.resp(200, poshmark_fixture())
    end)

    bypass
  end

  defp open_openai_bypass(count \\ 20) do
    bypass = Bypass.open()

    Application.put_env(
      :chat_app,
      :openai_embeddings_url,
      "http://localhost:#{bypass.port}/v1/embeddings"
    )

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      n = length(decoded["input"])
      resp_body = openai_fixture_for_count(n)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, resp_body)
    end)

    bypass
  end

  # Builds a valid eBay search JSON body with `count` synthetic items derived
  # from the real fixture so all required fields are present.
  defp stub_ebay_body(count) do
    base_items = Jason.decode!(ebay_fixture())["itemSummaries"]

    items =
      Stream.cycle(base_items)
      |> Stream.with_index()
      |> Enum.take(count)
      |> Enum.map(fn {item, idx} -> Map.put(item, "itemId", "v1|e2e|#{idx}") end)

    Jason.encode!(%{"total" => count, "itemSummaries" => items})
  end

  defp count_items, do: Repo.aggregate(ClothingItem, :count)
  defp count_price_history, do: Repo.aggregate(PriceHistory, :count)

  defp perform_ebay(query \\ "vintage levi") do
    ScrapeWorker.perform(%Oban.Job{args: %{"source" => "ebay", "query" => query}})
  end

  defp perform_depop(query \\ "vintage levi") do
    ScrapeWorker.perform(%Oban.Job{args: %{"source" => "depop", "query" => query}})
  end

  defp perform_poshmark(query \\ "vintage levi") do
    ScrapeWorker.perform(%Oban.Job{args: %{"source" => "poshmark", "query" => query}})
  end

  # ---------------------------------------------------------------------------
  # Test 5
  # full pipeline: scrape → normalize → deduplicate → embed: all items have embedding
  # ---------------------------------------------------------------------------

  test "full pipeline: scrape → normalize → deduplicate → embed: all items have embedding" do
    _ebay_bypass = open_ebay_bypass(stub_ebay_body(20))
    _openai_bypass = open_openai_bypass()

    perform_ebay()

    items = Repo.all(from(i in ClothingItem, where: i.source == "ebay"))

    assert length(items) == 20,
           "expected 20 eBay items, got #{length(items)}"

    for item <- items do
      assert is_binary(item.embedding) and byte_size(item.embedding) == 2048,
             "item #{item.id} has embedding: #{inspect(item.embedding && byte_size(item.embedding))}"
    end

    %{rows: [[vec_count]]} = Repo.query!("SELECT count(*) FROM clothing_vec")

    assert vec_count == 20,
           "expected 20 rows in clothing_vec, got #{vec_count} — " <>
             "EmbedWorker may not have been enqueued or executed, or VectorCodec error silently skipped embedding"
  end

  # ---------------------------------------------------------------------------
  # Test 6
  # full pipeline idempotency: second run same item count, doubled price_history
  # ---------------------------------------------------------------------------

  test "full pipeline idempotency: second run same item count, doubled price_history" do
    _ebay_bypass = open_ebay_bypass(stub_ebay_body(20))
    _openai_bypass = open_openai_bypass()

    perform_ebay()

    assert count_items() == 20,
           "after first run: expected 20 items, got #{count_items()}"

    assert count_price_history() == 20,
           "after first run: expected 20 price_history rows, got #{count_price_history()}"

    perform_ebay()

    assert count_items() == 20,
           "after second run: item count should stay 20 (deduplication), got #{count_items()}"

    assert count_price_history() == 40,
           "after second run: expected 40 price_history rows (20 per run), got #{count_price_history()} — " <>
             "price_history may only be written on insert, not on every upsert"
  end

  # ---------------------------------------------------------------------------
  # Test 7
  # full pipeline: eBay source HTTP failure isolated — other sources still persist
  # ---------------------------------------------------------------------------

  test "full pipeline: eBay source HTTP failure isolated — other sources still persist" do
    _ebay_bypass = open_ebay_bypass_500()
    _depop_bypass = open_depop_bypass()
    _poshmark_bypass = open_poshmark_bypass()
    _openai_bypass = open_openai_bypass()

    ebay_result = perform_ebay()
    depop_result = perform_depop()
    poshmark_result = perform_poshmark()

    assert match?({:error, _}, ebay_result),
           "expected eBay perform to return {:error, _} on 500, got: #{inspect(ebay_result)}"

    assert depop_result == :ok,
           "expected Depop perform to return :ok, got: #{inspect(depop_result)}"

    assert poshmark_result == :ok,
           "expected Poshmark perform to return :ok, got: #{inspect(poshmark_result)}"

    ebay_count =
      Repo.aggregate(from(i in ClothingItem, where: i.source == "ebay"), :count)

    assert ebay_count == 0,
           "expected 0 eBay items after HTTP failure, got #{ebay_count}"

    depop_count =
      Repo.aggregate(from(i in ClothingItem, where: i.source == "depop"), :count)

    poshmark_count =
      Repo.aggregate(from(i in ClothingItem, where: i.source == "poshmark"), :count)

    assert depop_count > 0,
           "expected Depop items to be persisted despite eBay failure, got 0"

    assert poshmark_count > 0,
           "expected Poshmark items to be persisted despite eBay failure, got 0 — " <>
             "single source failure may be crashing the entire worker"
  end
end
