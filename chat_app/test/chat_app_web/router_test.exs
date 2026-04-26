defmodule ChatAppWeb.RouterTest do
  use ChatAppWeb.ConnCase, async: true

  # Positive: root path is reachable
  test "GET / returns 200", %{conn: conn} do
    conn = get(conn, "/")
    html = html_response(conn, 200)
    assert html =~ "id=\"chat-input\""
  end

  # Negative: no JSON api scope is wired
  test "GET /api/* returns 404", %{conn: conn} do
    conn = get(conn, "/api/anything")
    assert html_response(conn, 404)
  end

  # Negative: unknown routes return 404 (Phoenix default)
  test "GET /does-not-exist returns 404", %{conn: conn} do
    conn = get(conn, "/does-not-exist")
    assert html_response(conn, 404)
  end
end
