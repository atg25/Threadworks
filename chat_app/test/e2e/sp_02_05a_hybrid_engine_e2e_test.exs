defmodule ChatApp.SP020005aHybridEngineE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.Search.HybridEngine
  alias ChatApp.Search.VectorStore
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Clothing.Item
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

  defp stub_embedder_error(bypass) do
    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(500, Jason.encode!(%{"error" => %{"message" => "api_down"}}))
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
  # E-01 — Positive: full pipeline — Item A first with rrf_score > 0
  # ---------------------------------------------------------------------------

  test "E-01: full pipeline — item A is first result, is a %ClothingItem{} struct, rrf_score > 0" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item_a =
      insert_item(%{
        title: "Vintage Levi Denim Jacket Secondhand",
        price: "25.00",
        url: "http://e.com/e01a"
      })

    item_b =
      insert_item(%{
        title: "Pink Silk Evening Gown Formal Wear",
        price: "80.00",
        url: "http://e.com/e01b",
        source: "depop"
      })

    item_c =
      insert_item(%{
        title: "Denim Jacket Indigo Blue Worn Preloved",
        price: "35.00",
        url: "http://e.com/e01c"
      })

    :ok = VectorStore.upsert(item_a.id, @fixture_a)
    :ok = VectorStore.upsert(item_b.id, @fixture_a)
    :ok = VectorStore.upsert(item_c.id, @fixture_a)
    :ok = FTS5Index.upsert(item_a.id)
    :ok = FTS5Index.upsert(item_b.id)
    :ok = FTS5Index.upsert(item_c.id)

    assert {:ok, [first | _rest]} = HybridEngine.search("vintage levi denim jacket")

    assert is_struct(first, ChatApp.Clothing.Item),
           "expected first result to be a %ClothingItem{} struct, got: #{inspect(first)}"

    assert first.id == item_a.id,
           "expected item_a (id=#{item_a.id}) as first result, got id=#{first.id}"

    assert first.rrf_score > 0,
           "expected rrf_score > 0, got: #{first.rrf_score}"
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: both pipelines empty → {:ok, []}
  # ---------------------------------------------------------------------------

  test "E-02: empty DB — both pipelines return empty — {:ok, []}" do
    bypass = open_bypass()
    stub_embedder(bypass)

    assert {:ok, []} = HybridEngine.search("anything")
  end

  # ---------------------------------------------------------------------------
  # E-03 — Negative: Embedder error propagated, not swallowed as {:ok, []}
  # ---------------------------------------------------------------------------

  test "E-03: Embedder {:error, _} is propagated — not swallowed as {:ok, []}" do
    bypass = open_bypass()
    stub_embedder_error(bypass)

    item = insert_item(%{title: "Vintage Jacket", price: "20.00", url: "http://e.com/e03"})
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)

    result = HybridEngine.search("test")

    assert match?({:error, _}, result),
           "expected {:error, _} when Embedder fails, got: #{inspect(result)}"
  end
end
