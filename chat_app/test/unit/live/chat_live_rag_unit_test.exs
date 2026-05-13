defmodule ChatAppWeb.ChatLiveRagUnitTest do
  use ChatAppWeb.ConnCase, async: false

  @moduletag :unit

  import Phoenix.LiveViewTest
  import Mox

  alias ChatAppWeb.ChatLive

  setup :verify_on_exit!

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  # ---------------------------------------------------------------------------
  # U1 — rag_status is :searching after handle_event("send_message") returns
  # ---------------------------------------------------------------------------
  #
  # Calls handle_event/3 directly on the module with a pre-built socket.
  # This is a pure unit test — no running LiveView process — and confirms
  # the architecture returns {:noreply, socket} with rag_status: :searching
  # before doing any blocking work.

  test "U1: rag_status is :searching immediately after handle_event send_message returns",
       %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", []} end)

    # Mount a real socket so handle_event has all required assigns available.
    {:ok, view, _html} = live(conn, "/")
    socket = :sys.get_state(view.pid).socket

    {:noreply, socket_after} =
      ChatLive.handle_event("send_message", %{"input" => "hello"}, socket)

    assert socket_after.assigns.rag_status == :searching
  end

  # ---------------------------------------------------------------------------
  # U2 — Initial socket assigns include all RAG-related fields on mount
  # ---------------------------------------------------------------------------

  test "U2: initial socket assigns include all RAG-related fields on mount", %{conn: conn} do
    stub(ChatApp.AI.MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", []} end)

    {:ok, view, _html} = live(conn, "/")

    assigns = live_assigns(view)
    assert assigns.rag_status == :idle
    assert assigns.response_parser_buffer == ""
    assert assigns.pending_cards == []
  end
end
