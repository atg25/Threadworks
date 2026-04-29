defmodule ChatAppWeb.Sprint19BMobileDrawerIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "sidebar carries mobile drawer and desktop fallback classes when open", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[data-sidebar-toggle='true']")
    |> render_click()

    assert has_element?(
             view,
             "#chat-sidebar.absolute.z-30.md\\:relative[data-sidebar-collapsed='false']"
           )
  end

  test "mobile backdrop is present only for the open state and hidden at desktop breakpoints",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "[data-mobile-backdrop='true']")

    view
    |> element("button[data-sidebar-toggle='true']")
    |> render_click()

    assert has_element?(view, "button[data-mobile-backdrop='true'].md\\:hidden")

    view
    |> element("[data-mobile-backdrop='true']")
    |> render_click()

    refute has_element?(view, "[data-mobile-backdrop='true']")
    assert has_element?(view, "#chat-sidebar[data-sidebar-collapsed='true']")
  end
end
