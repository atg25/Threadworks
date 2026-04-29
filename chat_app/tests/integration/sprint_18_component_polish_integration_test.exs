defmodule ChatAppWeb.Sprint18ComponentPolishIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  alias ChatApp.Conversations

  import Phoenix.LiveViewTest

  test "sidebar empty-state container exists when conversations list is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "[data-sidebar-empty-state]")
    assert has_element?(view, "[data-sidebar-empty-state] svg")
    assert has_element?(view, "[data-sidebar-empty-state]", "No conversations yet")
    refute has_element?(view, "[data-conversation-id]")
  end

  test "sidebar empty state is hidden for a populated conversation titled New conversation", %{conn: conn} do
    conversation = Conversations.create_conversation("test-session", %{})
    {:ok, _message} = Conversations.append_message(conversation.id, :assistant, "ready")

    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "[data-sidebar-empty-state]")
    assert has_element?(view, ~s([data-conversation-id="#{conversation.id}"]))
  end

  test "sidebar action controls render Heroicons instead of raw text labels", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(data-sidebar-action="new_conversation")
    assert html =~ ~s(data-sidebar-action-icon="plus")
    refute html =~ ">New<"
  end

  test "message action controls use semantic icon button component", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ ~s(data-message-action="regenerate")
    assert html =~ ~s(data-message-action="copy")
    assert html =~ ~s(class="icon-btn)
  end

  test "feedback up/down controls are absent from assistant bubbles", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='up']")
    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='down']")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "hello"})
    |> render_submit()

    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='up']")
    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='down']")
  end

  test "typing indicator uses skeleton block marker while sending", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "stream please"})
    |> render_submit()

    assert has_element?(view, "[data-typing-skeleton]")
    refute has_element?(view, "[data-typing-dots]")
  end
end
