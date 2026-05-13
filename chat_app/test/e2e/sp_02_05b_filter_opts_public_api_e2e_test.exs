defmodule ChatApp.SP020005bFilterOptsPublicApiE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Search.HybridEngine
  alias ChatApp.Search.VectorStore
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Repo

  @embeddings Code.eval_file(Path.join([__DIR__, "../fixtures/embeddings.exs"])) |> elem(0)
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

    Application.put_env(
      :chat_app,
      :openai_embeddings_url,
      "http://localhost:#{bypass.port}/v1/embeddings"
    )

    on_exit(fn -> Application.put_env(:chat_app, :openai_embeddings_url, original) end)
    bypass
  end

  defp insert_item(attrs) do
    base = %{
      source: "ebay",
      price: "25.00",
      title: "Jacket",
      url: "http://e.com/#{System.unique_integer()}"
    }

    {:ok, item} = Repo.insert(Item.changeset(%Item{}, Map.merge(base, attrs)))
    item
  end

  defp upsert_both(item) do
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)
  end

  # ---------------------------------------------------------------------------
  # E-01 — Positive: full pipeline through public API with source filter
  # ---------------------------------------------------------------------------

  test "E-01: full pipeline through Clothing.search_hybrid/2 with source filter returns only ebay items" do
    bypass = open_bypass()
    stub_embedder(bypass)

    ebay_a =
      insert_item(%{
        source: "ebay",
        title: "Vintage Jacket eBay A",
        url: "http://e.com/e01-ebay-a"
      })

    ebay_b =
      insert_item(%{
        source: "ebay",
        title: "Vintage Jacket eBay B",
        url: "http://e.com/e01-ebay-b"
      })

    depop =
      insert_item(%{
        source: "depop",
        title: "Vintage Jacket Depop",
        url: "http://e.com/e01-depop"
      })

    upsert_both(ebay_a)
    upsert_both(ebay_b)
    upsert_both(depop)

    assert {:ok, items} = Clothing.search_hybrid("jacket", source: :ebay)

    assert length(items) >= 1,
           "expected at least one result from public API with source: :ebay filter"

    Enum.each(items, fn item ->
      assert is_struct(item, ChatApp.Clothing.Item),
             "expected %Item{} struct, got: #{inspect(item)}"

      assert item.source == "ebay",
             "expected source == 'ebay', got: #{item.source}"

      assert item.rrf_score > 0,
             "expected rrf_score > 0, got: #{item.rrf_score}"
    end)

    ids = Enum.map(items, & &1.id)

    refute depop.id in ids,
           "expected depop item excluded by source: :ebay filter, got ids: #{inspect(ids)}"
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: all candidates filtered out by max_price → {:ok, []}
  # ---------------------------------------------------------------------------

  test "E-02: all candidates filtered out by max_price returns {:ok, []}" do
    bypass = open_bypass()
    stub_embedder(bypass)

    for i <- 1..5 do
      item =
        insert_item(%{
          price: "500.00",
          title: "Expensive Jacket #{i}",
          url: "http://e.com/e02-#{i}"
        })

      upsert_both(item)
    end

    assert {:ok, []} = HybridEngine.search("jacket", max_price: Decimal.new("10")),
           "expected {:ok, []} when all candidates exceed max_price filter"
  end
end
