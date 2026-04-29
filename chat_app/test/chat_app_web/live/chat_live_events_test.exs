defmodule ChatAppWeb.ChatLiveEventsTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # ── send_message happy path ──────────────────────────────────

  test "send_message appends user message to messages list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello AI"})

    html = render(view)
    assert html =~ "Hello AI"
  end

  test "send_message sets hero_state to false", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello"})

    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  test "send_message clears the input field", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello"})

    html = render(view)
    {:ok, doc} = Floki.parse_document(html)
    [textarea] = Floki.find(doc, "textarea#chat-input")
    assert textarea |> Floki.text() |> String.trim() == ""
  end

  test "hero_state never returns to true after first send", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("form") |> render_submit(%{"input" => "First"})
    refute has_element?(view, "[data-homepage-chat-intro]")

    pid = view.pid
    send(pid, :stream_done)
    render(view)

    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  # ── Guard: blank input ────────────────────────────────────────

  test "send_message with blank input does not add a message", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "   "})
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "send_message with blank input does not change hero_state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => ""})
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "new conversation remounts hero landing state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    assert render(view) =~ ~s(id="hero-landing-0")

    view
    |> element("button[data-new-chat-trigger='true']")
    |> render_click()

    assert render(view) =~ ~s(id="hero-landing-1")
  end

  # ── Guard: double-send while is_sending ───────────────────────

  test "second send while is_sending is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("form") |> render_submit(%{"input" => "First question"})
    view |> element("form") |> render_submit(%{"input" => "Second question"})

    html = render(view)
    assert html =~ "First question"
    refute html =~ "Second question"
  end

  # ── scroll_position ───────────────────────────────────────────

  test "scroll_position false hides scroll dock", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> render_hook("scroll_position", %{"at_bottom" => false})
    assert has_element?(view, "#scroll-cta-dock.hidden")
  end

  test "scroll_position true keeps dock hidden when already at bottom", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> render_hook("scroll_position", %{"at_bottom" => true})
    assert has_element?(view, "#scroll-cta-dock.hidden")
  end

  # ── handle_info: :stream_token ────────────────────────────────

  test ":stream_token appends to stream buffer and shows partial response", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("form") |> render_submit(%{"input" => "Hello"})

    pid = view.pid
    send(pid, {:stream_token, "Hello"})
    send(pid, {:stream_token, " world"})

    html = render(view)
    assert html =~ "Hello world"
  end

  test ":stream_token with empty string does not grow message list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_token, ""})
    html = render(view)
    # Stub sends "" (empty string) — no-op on buffer. Empty token must not add a second bubble.
    {:ok, doc} = Floki.parse_document(html)
    bubbles = Floki.find(doc, "[data-chat-message-bubble][data-role='assistant']")
    assert length(bubbles) == 1
  end

  # ── handle_info: :stream_done ─────────────────────────────────

  test ":stream_done clears is_sending and stream_buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_token, "Some answer"})
    send(pid, :stream_done)

    html = render(view)
    # typing indicator must be gone — is_sending is false after stream_done
    refute html =~ "animate-pulse"
    # assistant message must still be rendered
    assert html =~ "Some answer"
  end

  # ── handle_info: :stream_error ────────────────────────────────

  test ":stream_error appends error message to messages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_error, "connection refused"})

    html = render(view)
    assert html =~ "Error:"
  end

  test ":stream_error sets is_sending to false and stops typing indicator", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_error, "timeout"})

    html = render(view)
    refute html =~ "animate-pulse"
  end

  # ── Typing indicator ──────────────────────────────────────────

  test "typing indicator shown while is_sending and stream_buffer is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Capture return of render_submit: reflects state AFTER send_message sets
    # is_sending: true and stream_buffer: "" but BEFORE the stub's token is processed.
    html = view |> element("form") |> render_submit(%{"input" => "Q"})
    assert html =~ "animate-pulse"
  end

  test "typing indicator hidden once first token arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_token, "Hi"})

    html = render(view)
    refute html =~ "animate-pulse"
  end

  test "regenerate button is hidden on initial mount", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    refute has_element?(view, "button[phx-click='regenerate']")
  end

  test "regenerate button is hidden while is_sending and visible after stream_done", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("form") |> render_submit(%{"input" => "Q"})
    assert live_assigns(view).is_sending == true
    refute has_element?(view, "button[phx-click='regenerate']")

    pid = view.pid
    send(pid, {:stream_token, "A"})
    send(pid, :stream_done)

    assert live_assigns(view).is_sending == false
    assert has_element?(view, "button[phx-click='regenerate']")
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns
end
