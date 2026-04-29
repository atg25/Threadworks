defmodule ChatAppWeb.Sprint20MultiThemeIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "LiveView patches keep the theme selector JS-owned", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "patch check"})
    |> render_submit()

    assert has_element?(view, "[data-theme-source='js'][role='group'][aria-label='Theme']")

    for theme <- ["editorial", "swiss", "mid-century", "techno-brutalist"] do
      assert has_element?(view, "button[data-phx-theme='#{theme}']")
    end
  end
end
