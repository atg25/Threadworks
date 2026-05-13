defmodule ChatApp.SP040003AugmentE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.AI.StyleAdvisor
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Search.VectorStore

  @embeddings Code.eval_file(Path.join([__DIR__, "../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a

  # Bypass the OpenAI embedder so E2E tests run without a live API key —
  # same pattern used by all other E2E search tests (sp_02_05a, sp_02_05b, etc.).
  defp open_bypass do
    bypass = Bypass.open()
    original = Application.get_env(:chat_app, :openai_embeddings_url)
    Application.put_env(:chat_app, :openai_embeddings_url, "http://localhost:#{bypass.port}/v1/embeddings")
    on_exit(fn -> Application.put_env(:chat_app, :openai_embeddings_url, original) end)
    bypass
  end

  defp stub_embedder(bypass) do
    body =
      Jason.encode!(%{
        "object" => "list",
        "model" => "text-embedding-3-small",
        "data" => [%{"object" => "embedding", "index" => 0, "embedding" => @fixture_a}]
      })

    Bypass.stub(bypass, "POST", "/v1/embeddings", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, body)
    end)
  end

  defp insert_item(attrs) do
    {:ok, item} =
      Repo.insert(Item.changeset(%Item{}, Map.merge(%{source: "ebay"}, attrs)))

    item
  end

  setup do
    # Swap mock back to the real engine for E2E tests.
    original = Application.get_env(:chat_app, :hybrid_engine_module)
    Application.put_env(:chat_app, :hybrid_engine_module, ChatApp.Search.HybridEngine)
    on_exit(fn -> Application.put_env(:chat_app, :hybrid_engine_module, original) end)
    :ok
  end

  # ---------------------------------------------------------------------------
  # E1 — Live search returns results for a known clothing query
  # ---------------------------------------------------------------------------

  test "E1: live search returns results for a known clothing query" do
    bypass = open_bypass()
    stub_embedder(bypass)

    item = insert_item(%{title: "Vintage Levi Denim Jacket Secondhand", price: "25.00", url: "http://e.com/e1"})
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)

    {:ok, prompt, items} = StyleAdvisor.augment("vintage denim jacket")
    assert String.contains?(prompt, "AVAILABLE ITEMS:")
    assert length(items) > 0
    assert Enum.all?(items, &match?(%Item{}, &1))
  end

  # ---------------------------------------------------------------------------
  # E2 — Live search returns no results for a nonsense query
  # ---------------------------------------------------------------------------

  test "E2: live search returns no results for a nonsense query" do
    bypass = open_bypass()
    stub_embedder(bypass)

    {:ok, prompt, items} = StyleAdvisor.augment("xyzzy foobar nonsense query 99999")
    assert items == []
    refute String.contains?(prompt, "AVAILABLE ITEMS:")
  end
end
