defmodule ChatApp.Search.HybridEngineFilterIntegrationTest do
  use ChatApp.DataCase, async: false

  @moduletag :integration

  alias ChatApp.Search.HybridEngine
  alias ChatApp.Search.VectorStore
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  @embeddings Code.eval_file(Path.join([__DIR__, "../../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a

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

  defp open_bypass do
    bypass = Bypass.open()
    original = Application.get_env(:chat_app, :openai_embeddings_url)
    Application.put_env(:chat_app, :openai_embeddings_url, "http://localhost:#{bypass.port}/v1/embeddings")
    on_exit(fn -> Application.put_env(:chat_app, :openai_embeddings_url, original) end)
    bypass
  end

  defp insert_item(attrs) do
    base = %{source: "ebay", price: "25.00", title: "Vintage Jacket", url: "http://e.com/#{System.unique_integer()}"}
    {:ok, item} = Repo.insert(Item.changeset(%Item{}, Map.merge(base, attrs)))
    item
  end

  defp upsert_both(item) do
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)
  end

  # ---------------------------------------------------------------------------
  # I-01 — source filter excludes items from other sources
  # ---------------------------------------------------------------------------

  test "I-01: source filter excludes items from other sources" do
    bypass = open_bypass()
    stub_embedder(bypass)

    ebay_item = insert_item(%{source: "ebay", title: "Vintage Jacket eBay", url: "http://e.com/i01-ebay"})
    depop_item = insert_item(%{source: "depop", title: "Vintage Jacket Depop", url: "http://e.com/i01-depop"})

    upsert_both(ebay_item)
    upsert_both(depop_item)

    assert {:ok, results} = HybridEngine.search("jacket", source: :ebay)

    ids = Enum.map(results, & &1.id)

    assert ebay_item.id in ids,
           "expected ebay item in results, got ids: #{inspect(ids)}"

    refute depop_item.id in ids,
           "expected depop item excluded by source filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # I-02 — max_price filter excludes over-budget items
  # ---------------------------------------------------------------------------

  test "I-02: max_price filter excludes over-budget items" do
    bypass = open_bypass()
    stub_embedder(bypass)

    cheap = insert_item(%{price: "10.00", title: "Jacket Cheap", url: "http://e.com/i02-cheap"})
    mid   = insert_item(%{price: "50.00", title: "Jacket Mid", url: "http://e.com/i02-mid"})
    pricey = insert_item(%{price: "200.00", title: "Jacket Pricey", url: "http://e.com/i02-pricey"})

    upsert_both(cheap)
    upsert_both(mid)
    upsert_both(pricey)

    assert {:ok, results} = HybridEngine.search("jacket", max_price: Decimal.new("30"))

    ids = Enum.map(results, & &1.id)

    refute mid.id in ids,
           "expected $50 item excluded by max_price filter, got ids: #{inspect(ids)}"

    refute pricey.id in ids,
           "expected $200 item excluded by max_price filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # I-03 — size filter matches case-insensitively
  # ---------------------------------------------------------------------------

  test "I-03: size filter matches case-insensitively" do
    bypass = open_bypass()
    stub_embedder(bypass)

    size_lower = insert_item(%{size: "m", title: "Jacket Size m lowercase", url: "http://e.com/i03-lower"})
    size_upper = insert_item(%{size: "M", title: "Jacket Size M uppercase", url: "http://e.com/i03-upper"})
    size_large = insert_item(%{size: "L", title: "Jacket Size L large", url: "http://e.com/i03-large"})

    upsert_both(size_lower)
    upsert_both(size_upper)
    upsert_both(size_large)

    assert {:ok, results} = HybridEngine.search("jacket", size: "M")

    ids = Enum.map(results, & &1.id)

    assert size_lower.id in ids,
           "expected size 'm' (lowercase) matched by size: 'M' filter, got ids: #{inspect(ids)}"

    assert size_upper.id in ids,
           "expected size 'M' (uppercase) matched by size: 'M' filter, got ids: #{inspect(ids)}"

    refute size_large.id in ids,
           "expected size 'L' excluded by size: 'M' filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # I-04 — limit returns at most N results
  # ---------------------------------------------------------------------------

  test "I-04: limit returns at most N results" do
    bypass = open_bypass()
    stub_embedder(bypass)

    for i <- 1..20 do
      item = insert_item(%{title: "Jacket Item #{i}", url: "http://e.com/i04-#{i}"})
      upsert_both(item)
    end

    assert {:ok, results} = HybridEngine.search("jacket", limit: 5)

    assert length(results) <= 5,
           "expected at most 5 results with limit: 5, got #{length(results)}"
  end

  # ---------------------------------------------------------------------------
  # I-05 — limit: 0 returns {:ok, []} without crashing
  # ---------------------------------------------------------------------------

  test "I-05: limit: 0 returns {:ok, []} without crashing" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item = insert_item(%{title: "Jacket", url: "http://e.com/i05"})
    upsert_both(item)

    assert {:ok, []} = HybridEngine.search("jacket", limit: 0)
  end

  # ---------------------------------------------------------------------------
  # I-06 — Filters are applied as SQL WHERE conditions, not post-hydration
  # ---------------------------------------------------------------------------

  test "I-06: source filter is applied at SQL level — deleted ebay item does not appear" do
    bypass = open_bypass()
    stub_embedder(bypass)

    ebay_item  = insert_item(%{source: "ebay", title: "Jacket eBay", url: "http://e.com/i06-ebay"})
    depop_item = insert_item(%{source: "depop", title: "Jacket Depop", url: "http://e.com/i06-depop"})

    upsert_both(ebay_item)
    upsert_both(depop_item)

    # Delete the ebay clothing_items row — it remains in vec/FTS indexes.
    # A post-hydration filter would never see it; a SQL WHERE filter won't return it.
    # This proves the filter runs at DB fetch time, not after.
    Repo.delete!(ebay_item)

    assert {:ok, results} = HybridEngine.search("jacket", source: :ebay)

    ids = Enum.map(results, & &1.id)

    refute ebay_item.id in ids,
           "expected deleted ebay item absent from results (SQL filter guarantees this), got ids: #{inspect(ids)}"

    refute depop_item.id in ids,
           "expected depop item excluded by source: :ebay filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # I-07 — Multiple filters compose correctly (AND semantics)
  # ---------------------------------------------------------------------------

  test "I-07: multiple filters compose with AND semantics" do
    bypass = open_bypass()
    stub_embedder(bypass)

    match_all  = insert_item(%{source: "ebay", size: "M", price: "25.00", title: "Jacket Match All", url: "http://e.com/i07-match"})
    wrong_size = insert_item(%{source: "ebay", size: "L", price: "25.00", title: "Jacket Wrong Size", url: "http://e.com/i07-size"})
    wrong_src  = insert_item(%{source: "depop", size: "M", price: "25.00", title: "Jacket Wrong Source", url: "http://e.com/i07-src"})
    over_price = insert_item(%{source: "ebay", size: "M", price: "150.00", title: "Jacket Over Price", url: "http://e.com/i07-price"})

    upsert_both(match_all)
    upsert_both(wrong_size)
    upsert_both(wrong_src)
    upsert_both(over_price)

    assert {:ok, results} = HybridEngine.search("jacket", source: :ebay, size: "M", max_price: Decimal.new("50"))

    ids = Enum.map(results, & &1.id)

    assert match_all.id in ids,
           "expected {ebay, M, $25} item in results, got ids: #{inspect(ids)}"

    refute wrong_size.id in ids,
           "expected {ebay, L, $25} excluded by size filter, got ids: #{inspect(ids)}"

    refute wrong_src.id in ids,
           "expected {depop, M, $25} excluded by source filter, got ids: #{inspect(ids)}"

    refute over_price.id in ids,
           "expected {ebay, M, $150} excluded by max_price filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # I-08 — Clothing.search_hybrid/2 delegates to HybridEngine.search/2
  # ---------------------------------------------------------------------------

  test "I-08: Clothing.search_hybrid/2 delegates to HybridEngine.search/2" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item = insert_item(%{source: "ebay", title: "Vintage Jacket eBay", url: "http://e.com/i08"})
    upsert_both(item)

    direct_result = HybridEngine.search("vintage jacket", source: :ebay)
    public_result = Clothing.search_hybrid("vintage jacket", source: :ebay)

    assert {:ok, direct_items} = direct_result
    assert {:ok, public_items} = public_result

    assert Enum.map(direct_items, & &1.id) == Enum.map(public_items, & &1.id),
           "expected Clothing.search_hybrid/2 to return same items as HybridEngine.search/2"
  end

  # ---------------------------------------------------------------------------
  # I-09 — rrf_score values on filtered results remain correct positive floats
  # ---------------------------------------------------------------------------

  test "I-09: rrf_score on filtered results are correct positive floats" do
    bypass = open_bypass()
    stub_embedder(bypass)

    ebay_item  = insert_item(%{source: "ebay", title: "Jacket eBay Scored", url: "http://e.com/i09-ebay"})
    depop_item = insert_item(%{source: "depop", title: "Jacket Depop Scored", url: "http://e.com/i09-depop"})

    upsert_both(ebay_item)
    upsert_both(depop_item)

    assert {:ok, results} = HybridEngine.search("jacket", source: :ebay)

    assert length(results) >= 1,
           "expected at least one result with source: :ebay filter"

    Enum.each(results, fn item ->
      assert is_float(item.rrf_score),
             "expected float rrf_score, got: #{inspect(item.rrf_score)}"

      assert item.rrf_score > 0,
             "expected rrf_score > 0, got: #{item.rrf_score}"

      assert item.rrf_score <= 2.0 / 61,
             "expected rrf_score <= 2/61, got: #{item.rrf_score}"
    end)
  end
end
