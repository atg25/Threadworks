defmodule ChatAppWeb.ChatLiveCardRenderTest do
  use ChatAppWeb.ConnCase, async: false

  @moduletag :integration

  import Phoenix.LiveViewTest
  import Mox

  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item

  setup :verify_on_exit!

  setup do
    stub(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:ok, []} end)
    :ok
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp wait_until(fun, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn -> fun.() end)
    |> Stream.take_while(fn result ->
      not result and System.monotonic_time(:millisecond) < deadline
    end)
    |> Stream.each(fn _ -> :timer.sleep(50) end)
    |> Stream.run()

    fun.()
  end

  defp insert_item(overrides \\ %{}) do
    base = %{
      title: "Test Item",
      price: "30.00",
      url: "http://example.com/#{System.unique_integer()}",
      source: "ebay"
    }

    {:ok, item} = Clothing.create_item(Map.merge(base, overrides))
    item
  end

  # ---------------------------------------------------------------------------
  # I1 — Cards rendered below assistant message after stream_done
  # ---------------------------------------------------------------------------

  test "I1: cards rendered below assistant message after stream_done", %{conn: conn} do
    item = insert_item(%{title: "Vintage Jacket"})

    rag_item = %Item{
      id: item.id,
      title: item.title,
      price: item.price,
      url: item.url,
      source: item.source,
      rrf_score: 0.05
    }

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      {:ok, "base", [rag_item, rag_item]}
    end)

    {:ok, view, _html} = live(conn, "/")

    card_json = Jason.encode!(%{"cards" => [%{"item_id" => item.id, "reason" => "Good fit"}]})

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "jackets"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end)

    send(view.pid, {:stream_token, card_json})
    :timer.sleep(100)
    send(view.pid, :stream_done)

    assert wait_until(fn -> live_assigns(view).rag_status == :idle end)

    html = render(view)
    assert html =~ item.title
    assert html =~ "Good fit"
    assert html =~ ~s(data-product-card)
  end

  # ---------------------------------------------------------------------------
  # I2 — Message without cards renders no product card elements
  # ---------------------------------------------------------------------------

  test "I2: message without cards renders no product card elements", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", []} end)

    {:ok, view, _html} = live(conn, "/")

    # Send a message that goes through the clarify path (no items → clarify question)
    # so we get an assistant message without cards
    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "hi"})

    assert wait_until(fn -> live_assigns(view).rag_status == :idle end)

    html = render(view)
    refute html =~ ~s(data-product-card)
  end

  # ---------------------------------------------------------------------------
  # I3 — "Searching..." indicator visible when rag_status is :searching
  # ---------------------------------------------------------------------------

  test "I3: Searching indicator visible when rag_status is :searching", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      Process.sleep(5000)
      {:ok, "base", []}
    end)

    {:ok, view, _html} = live(conn, "/")

    html =
      view
      |> element("form[phx-submit='send_message']")
      |> render_submit(%{"input" => "test query"})

    assert html =~ ~s(data-rag-indicator="searching")
  end

  # ---------------------------------------------------------------------------
  # I4 — "Searching..." indicator not rendered when rag_status is :idle
  # ---------------------------------------------------------------------------

  test "I4: Searching indicator not rendered when rag_status is :idle", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", []} end)

    {:ok, view, _html} = live(conn, "/")

    html = render(view)
    refute html =~ ~s(data-rag-indicator="searching")
  end

  # ---------------------------------------------------------------------------
  # I5 — Cards survive LiveView re-render (stored in message struct, not pending_cards)
  # ---------------------------------------------------------------------------

  test "I5: cards survive LiveView re-render stored in message struct not pending_cards",
       %{conn: conn} do
    item = insert_item(%{title: "Surviving Item"})

    rag_item = %Item{
      id: item.id,
      title: item.title,
      price: item.price,
      url: item.url,
      source: item.source,
      rrf_score: 0.05
    }

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      {:ok, "base", [rag_item, rag_item]}
    end)

    {:ok, view, _html} = live(conn, "/")

    card_json =
      Jason.encode!(%{"cards" => [%{"item_id" => item.id, "reason" => "Nice find"}]})

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "test"})

    # Wait for streaming to start (rag_status becomes :streaming after do_rag runs)
    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end)

    send(view.pid, {:stream_token, card_json})
    :timer.sleep(100)
    send(view.pid, :stream_done)

    # Wait for stream_done to be processed
    assert wait_until(fn -> live_assigns(view).rag_status == :idle end)

    assigns = live_assigns(view)
    # pending_cards is cleared by stream_done
    assert assigns.pending_cards == []
    assert assigns.rag_status == :idle

    # But the item name must still be visible in the rendered HTML from message struct
    html = render(view)
    assert html =~ item.title
  end

  test "I6: cards are restored after remounting the chat", %{conn: conn} do
    item = insert_item(%{title: "Reloaded Card Item"})

    rag_item = %Item{
      id: item.id,
      title: item.title,
      price: item.price,
      url: item.url,
      source: item.source,
      rrf_score: 0.05
    }

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      {:ok, "base", [rag_item, rag_item]}
    end)

    {:ok, view, _html} = live(conn, "/")

    card_json =
      Jason.encode!(%{"cards" => [%{"item_id" => item.id, "reason" => "Still relevant"}]})

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "reload"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end)

    send(view.pid, {:stream_token, card_json})
    send(view.pid, :stream_done)

    assert wait_until(fn -> live_assigns(view).rag_status == :idle end)

    {:ok, reloaded_view, _html} = live(conn, "/")

    assigns = live_assigns(reloaded_view)
    last_msg = List.last(assigns.messages)

    assert [%{item: %{id: item_id}, reason: "Still relevant"}] = last_msg.cards
    assert item_id == item.id
    assert render(reloaded_view) =~ item.title
  end
end
