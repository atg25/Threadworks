defmodule ChatApp.SP040004ChatLiveRagE2ETest do
  use ChatAppWeb.ConnCase, async: false

  @moduletag :e2e

  import Phoenix.LiveViewTest
  import Mox

  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Search.VectorStore

  @embeddings Code.eval_file(Path.join([__DIR__, "../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a

  setup :verify_on_exit!

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

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

  defp insert_item_with_embeddings(attrs) do
    base = %{
      title: attrs[:title] || "Vintage Denim Jacket Secondhand",
      price: attrs[:price] || "55.00",
      url: attrs[:url] || "http://example.com/#{System.unique_integer()}",
      source: "ebay"
    }

    {:ok, item} = Clothing.create_item(Map.merge(base, Map.drop(attrs, [:title, :price, :url])))
    :ok = VectorStore.upsert(item.id, @fixture_a)
    :ok = FTS5Index.upsert(item.id)
    item
  end

  setup do
    original = Application.get_env(:chat_app, :hybrid_engine_module)
    original_openai = Application.get_env(:chat_app, :openai_module)
    Application.put_env(:chat_app, :hybrid_engine_module, ChatApp.Search.HybridEngine)
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

    on_exit(fn ->
      Application.put_env(:chat_app, :hybrid_engine_module, original)
      Application.put_env(:chat_app, :openai_module, original_openai)
    end)

    :ok
  end

  defp eventually(fun, opts \\ []) do
    timeout = opts[:timeout] || 5000
    interval = 100
    deadline = System.monotonic_time(:millisecond) + timeout
    do_eventually(fun, deadline, interval)
  end

  defp do_eventually(fun, deadline, interval) do
    if fun.() do
      true
    else
      now = System.monotonic_time(:millisecond)

      if now < deadline do
        :timer.sleep(interval)
        do_eventually(fun, deadline, interval)
      else
        false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # E1 — Full RAG flow: rag_status transitions and pending_cards populated
  # ---------------------------------------------------------------------------

  test "E1: full RAG flow — rag_status transitions and pending_cards populated", %{conn: conn} do
    bypass = open_bypass()
    stub_embedder(bypass)

    item = insert_item_with_embeddings(%{title: "Vintage Denim Jacket under 60 Secondhand"})

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      chunk = """
      data: {"choices":[{"delta":{"content":"{\\"cards\\": [{\\"item_id\\": #{item.id}, \\"reason\\": \\"Good pick\\"}]}"}}]}

      data: [DONE]
      """

      Req.Test.text(conn, chunk)
    end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[phx-submit='send_message']")
    |> render_submit(%{"input" => "vintage denim jacket under $60"})

    assert live_assigns(view).rag_status in [:searching, :streaming, :idle]

    assert eventually(
             fn -> live_assigns(view).rag_status == :idle end,
             timeout: 8000
           )

    assigns = live_assigns(view)

    last_msg = List.last(assigns.messages)
    assert Map.get(last_msg, :cards, []) != []
    assert Enum.all?(last_msg.cards, &match?(%Item{}, &1.item))
  end

  # ---------------------------------------------------------------------------
  # E2 — Clarify path: clarifying question sent without OpenAI streaming call
  # ---------------------------------------------------------------------------

  test "E2: clarify path sends clarifying question, rag_status returns to idle", %{conn: conn} do
    bypass = open_bypass()
    stub_embedder(bypass)

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      items = [%ChatApp.Clothing.Item{id: 99, rrf_score: 0.005}]
      {:ok, "base prompt", items}
    end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[phx-submit='send_message']")
    |> render_submit(%{"input" => "xyzzy abc nonsense query"})

    assert eventually(
             fn -> live_assigns(view).rag_status == :idle end,
             timeout: 5000
           )

    html = render(view)
    assert html =~ "Could you tell me more about"
    assert live_assigns(view).rag_status == :idle
    assert live_assigns(view).is_sending == false
  end

  # ---------------------------------------------------------------------------
  # E3 — Empty search: base prompt used, streaming proceeds without AVAILABLE ITEMS
  # ---------------------------------------------------------------------------

  test "E3: empty search result uses base prompt and streaming proceeds normally", %{conn: conn} do
    bypass = open_bypass()
    stub_embedder(bypass)

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base prompt", []} end)

    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[phx-submit='send_message']")
    |> render_submit(%{"input" => "what time is it?"})

    assert eventually(
             fn -> live_assigns(view).rag_status == :idle end,
             timeout: 5000
           )

    refute render(view) =~ "AVAILABLE ITEMS"
  end
end
