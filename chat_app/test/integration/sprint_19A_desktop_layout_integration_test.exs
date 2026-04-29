defmodule ChatAppWeb.Sprint19ADesktopLayoutIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.Conversations

  test "sidebar collapses and expands via header toggle on desktop", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(
             view,
             ~s(#chat-sidebar[data-sidebar-collapsed="true"][style*="width: 0px"])
           )

    view
    |> element("button[data-sidebar-toggle='true']")
    |> render_click()

    assert has_element?(
             view,
             ~s(#chat-sidebar[data-sidebar-collapsed="false"][style*="width: 16rem"])
           )

    view
    |> element("button[data-sidebar-toggle='true']")
    |> render_click()

    assert has_element?(
             view,
             ~s(#chat-sidebar[data-sidebar-collapsed="true"][style*="width: 0px"])
           )
  end

  test "API cost tracker is completely removed from the DOM", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "[data-usage-cost]")
  end

  test "header icon buttons are keyboard accessible", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, "button[data-sidebar-toggle='true'][aria-label='Expand sidebar']")

    assert has_element?(
             view,
             "button[data-new-chat-trigger='true'][aria-label='Start a new conversation']"
           )

    assert has_element?(
             view,
             "button[phx-click='toggle_settings'][aria-label='Conversation settings']"
           )

    assert has_element?(view, "button[data-sidebar-toggle='true'].focus-ring")
    assert has_element?(view, "button[phx-click='toggle_settings'].focus-ring")
  end

  test "sidebar events ignore conversations from another session", %{conn: conn} do
    other = Conversations.create_conversation("other-session", %{title: "Other session"})
    {:ok, _message} = Conversations.append_message(other.id, :user, "secret from another session")

    {:ok, view, _html} = live(conn, "/")

    render_click(view, "switch_conversation", %{"id" => Integer.to_string(other.id)})
    refute render(view) =~ "secret from another session"

    render_click(view, "rename_conversation", %{
      "id" => Integer.to_string(other.id),
      "title" => "Renamed by attacker"
    })

    assert Conversations.get_conversation!(other.id).title == "Other session"

    render_click(view, "delete_conversation", %{"id" => Integer.to_string(other.id)})
    assert Conversations.get_conversation!(other.id).title == "Other session"
  end
end
