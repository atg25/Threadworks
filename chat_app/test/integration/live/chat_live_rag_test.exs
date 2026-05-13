defmodule ChatAppWeb.ChatLiveRagTest do
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

  defp wait_until(fun, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) < deadline do
        :timer.sleep(50)
        do_wait(fun, deadline)
      else
        false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # I1 — :searching emitted to client before augment begins
  # ---------------------------------------------------------------------------

  test "I1: rag_status is :searching before augment/2 returns", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", []} end)

    # Mount a connected socket and call handle_event directly — the only way to
    # observe the intermediate :searching state before {:do_rag} runs.
    {:ok, view, _html} = live(conn, "/")
    socket = :sys.get_state(view.pid).socket

    {:noreply, socket_after} =
      ChatAppWeb.ChatLive.handle_event("send_message", %{"input" => "query"}, socket)

    assert socket_after.assigns.rag_status == :searching
    assert socket_after.assigns.is_sending == true
  end

  # ---------------------------------------------------------------------------
  # I2 — response_parser_buffer reset to "" on stream completion
  # ---------------------------------------------------------------------------

  test "I2: response_parser_buffer is reset to empty string on stream_done", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Simulate a token arriving during streaming state
    send(view.pid, {:stream_token, "some text"})
    :timer.sleep(50)

    send(view.pid, :stream_done)
    :timer.sleep(100)

    assigns = live_assigns(view)
    assert assigns.response_parser_buffer == ""
    assert assigns.rag_status == :idle
  end

  # ---------------------------------------------------------------------------
  # I3 — pending_cards populated with full ClothingItem structs via DB lookup
  # ---------------------------------------------------------------------------

  test "I3: pending_cards populated with full ClothingItem structs on stream_token", %{conn: conn} do
    item = insert_item(%{title: "Vintage Denim Jacket"})
    card_json = Jason.encode!(%{"cards" => [%{"item_id" => item.id, "reason" => "Good pick"}]})

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      high_score_item = %Item{
        id: item.id,
        rrf_score: 0.05,
        title: item.title,
        price: item.price,
        url: item.url,
        source: item.source
      }

      {:ok, "augmented prompt", [high_score_item, high_score_item]}
    end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "jackets"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end, 2000)

    send(view.pid, {:stream_token, card_json})
    :timer.sleep(200)

    assigns = live_assigns(view)
    assert length(assigns.pending_cards) >= 1
    card = hd(assigns.pending_cards)
    assert card.item.id == item.id
    assert card.reason == "Good pick"
    assert match?(%Item{}, card.item)
  end

  # ---------------------------------------------------------------------------
  # I4 — Existing non-RAG message handling unchanged after refactor
  # ---------------------------------------------------------------------------

  test "I4: clarify path renders question and does not corrupt message list", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      items = [
        %Item{
          rrf_score: 0.001,
          id: 1,
          title: "X",
          price: Decimal.new("10.00"),
          url: "http://e.com",
          source: "ebay"
        }
      ]

      {:ok, "base", items}
    end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "hello"})

    assert wait_until(fn -> live_assigns(view).rag_status == :idle end, 2000)

    assigns = live_assigns(view)
    messages = assigns.messages
    contents = Enum.map(messages, & &1.content)
    assert "hello" in contents
    assert Enum.any?(contents, &String.contains?(&1, "Could you tell me more"))
    assert assigns.rag_status == :idle
  end

  # ---------------------------------------------------------------------------
  # I5 — Multiple sequential stream chunks accumulate pending_cards correctly
  # ---------------------------------------------------------------------------

  test "I5: multiple sequential stream chunks accumulate pending_cards correctly", %{conn: conn} do
    item_1 = insert_item(%{title: "Item One"})
    item_2 = insert_item(%{title: "Item Two"})

    chunk_1 = "Some text "
    chunk_2 = Jason.encode!(%{"cards" => [%{"item_id" => item_1.id, "reason" => "A"}]})
    chunk_3 = Jason.encode!(%{"cards" => [%{"item_id" => item_2.id, "reason" => "B"}]})

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      items = [
        %Item{id: item_1.id, rrf_score: 0.05, title: "Item One", price: Decimal.new("30.00"), url: "http://e.com/1", source: "ebay"},
        %Item{id: item_2.id, rrf_score: 0.05, title: "Item Two", price: Decimal.new("30.00"), url: "http://e.com/2", source: "ebay"}
      ]

      {:ok, "augmented prompt", items}
    end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "items"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end, 2000)

    send(view.pid, {:stream_token, chunk_1})
    :timer.sleep(50)
    send(view.pid, {:stream_token, chunk_2})
    :timer.sleep(50)
    send(view.pid, {:stream_token, chunk_3})
    :timer.sleep(200)

    assigns = live_assigns(view)
    assert length(assigns.pending_cards) == 2
    ids = Enum.map(assigns.pending_cards, & &1.item.id)
    assert item_1.id in ids
    assert item_2.id in ids
  end

  # ---------------------------------------------------------------------------
  # M1 — nil DB lookup for unknown item_id is silently dropped, valid cards kept
  # ---------------------------------------------------------------------------

  test "M1: unknown item_id is silently dropped, valid card is kept", %{conn: conn} do
    real_item = insert_item(%{title: "Real Item"})

    card_json =
      Jason.encode!(%{
        "cards" => [
          %{"item_id" => real_item.id, "reason" => "Good"},
          %{"item_id" => 99_999_999, "reason" => "Ghost"}
        ]
      })

    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      items = [
        %Item{id: real_item.id, rrf_score: 0.05, title: "Real Item", price: Decimal.new("30.00"), url: "http://e.com/r", source: "ebay"},
        %Item{id: real_item.id, rrf_score: 0.05, title: "Real Item", price: Decimal.new("30.00"), url: "http://e.com/r2", source: "ebay"}
      ]

      {:ok, "augmented prompt", items}
    end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "real item"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end, 2000)

    send(view.pid, {:stream_token, card_json})
    :timer.sleep(200)

    assigns = live_assigns(view)
    assert length(assigns.pending_cards) == 1
    assert hd(assigns.pending_cards).item.id == real_item.id
  end

  # ---------------------------------------------------------------------------
  # M2 — augment returning {:ok, base_prompt, []} does not crash ChatLive
  # ---------------------------------------------------------------------------

  test "M2: augment returning {:ok, base_prompt, []} does not crash the LiveView", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base prompt", []} end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "anything"})

    :timer.sleep(300)
    assert Process.alive?(view.pid)
    assert wait_until(fn -> live_assigns(view).rag_status == :idle end, 3000)
  end

  # ---------------------------------------------------------------------------
  # M3 — :stream_error resets rag_status, buffer, and pending_cards
  # ---------------------------------------------------------------------------

  test "M3: stream_error resets rag_status, buffer, and pending_cards to clean state",
       %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ ->
      items = [
        %Item{rrf_score: 0.05, id: 1, title: "X", price: Decimal.new("10.00"), url: "http://e.com", source: "ebay"},
        %Item{rrf_score: 0.05, id: 2, title: "Y", price: Decimal.new("10.00"), url: "http://e.com/2", source: "ebay"}
      ]

      {:ok, "augmented", items}
    end)

    {:ok, view, _html} = live(conn, "/")

    view |> element("form[phx-submit='send_message']") |> render_submit(%{"input" => "query"})

    assert wait_until(fn -> live_assigns(view).rag_status == :streaming end, 2000)

    send(view.pid, {:stream_token, "partial json"})
    :timer.sleep(50)

    send(view.pid, {:stream_error, :timeout})
    :timer.sleep(100)

    assigns = live_assigns(view)
    assert assigns.rag_status == :idle
    assert assigns.response_parser_buffer == ""
    assert assigns.pending_cards == []
    assert assigns.is_sending == false
  end
end
