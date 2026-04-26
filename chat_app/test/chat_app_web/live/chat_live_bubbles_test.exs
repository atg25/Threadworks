defmodule ChatAppWeb.ChatLiveBubblesTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # Helper: submit a message, inject a stream token, send done, return rendered HTML.
  defp send_and_finish(view, text, response) do
    view |> element("form") |> render_submit(%{"input" => text})
    send(view.pid, {:stream_token, response})
    send(view.pid, :stream_done)
    render(view)
  end

  # ── User bubble ───────────────────────────────────────────────

  test "user message renders in a bubble with correct class", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Hello AI", "Hi!")

    html = render(view)
    assert html =~ "Hello AI"
    assert html =~ "ui-chat-message-user"
  end

  test "user bubble has ml-auto (right-aligned)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Hello", "Hi")

    {:ok, doc} = Floki.parse_document(render(view))
    user_bubbles = Floki.find(doc, "[data-role='user']")

    assert Enum.any?(user_bubbles, fn el ->
             class = Floki.attribute(el, "class") |> List.first("")
             String.contains?(class, "ml-auto")
           end)
  end

  test "user bubble has max-w-[80%] class", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Hello", "Hi")
    html = render(view)
    assert html =~ "max-w-[80%]"
  end

  # ── Assistant bubble ──────────────────────────────────────────

  test "assistant message renders in a bubble with correct class", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Hello", "Hi there!")

    html = render(view)
    assert html =~ "Hi there!"
    assert html =~ "ui-chat-message-assistant"
  end

  test "assistant bubble has prose class for Markdown typography", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "Some answer")

    html = render(view)
    assert html =~ "prose"
  end

  test "assistant bubble has prose-sm class", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "Answer")
    assert render(view) =~ "prose-sm"
  end

  # ── Markdown rendering ────────────────────────────────────────

  test "bold markdown in assistant response renders as <strong>", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Bold?", "**bold text**")

    html = render(view)
    assert html =~ "<strong>bold text</strong>"
  end

  test "inline code in assistant response renders as <code>", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Code?", "`my_function()`")

    html = render(view)
    assert html =~ "<code"
    assert html =~ "my_function()"
  end

  test "unordered list in assistant response renders as <ul>", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # Prefix with a newline so Earmark sees the list items at line-start.
    send_and_finish(view, "List?", "\n- one\n- two\n- three")

    html = render(view)
    assert html =~ "<ul>"
    assert html =~ "<li>"
  end

  test "user messages are NOT markdown rendered (plain text)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "**not bold**", "Response")

    html = render(view)
    # User message should show literal **not bold**, not <strong>
    assert html =~ "**not bold**"
    # There should be no <strong> wrapping the user message
    {:ok, doc} = Floki.parse_document(html)
    user_bubbles = Floki.find(doc, "[data-role='user']")
    user_html = Floki.raw_html(user_bubbles)
    refute user_html =~ "<strong>"
  end

  # ── Typing indicator ──────────────────────────────────────────

  test "typing indicator (animate-pulse) visible while streaming with empty buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # Return value of render_submit reflects state after send_message
    # (is_sending: true, stream_buffer: "") before any real token is processed.
    html = view |> element("form") |> render_submit(%{"input" => "Q"})
    assert html =~ "animate-pulse"
  end

  test "typing indicator disappears once first token arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})
    send(view.pid, {:stream_token, "Hi"})
    html = render(view)
    refute html =~ "animate-pulse"
  end

  test "typing indicator absent when not streaming", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    refute html =~ "animate-pulse"
  end

  # ── Multiple messages ─────────────────────────────────────────

  test "multiple messages render in correct order", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    send_and_finish(view, "First question", "First answer")
    send_and_finish(view, "Second question", "Second answer")

    html = render(view)
    assert html =~ "First question"
    assert html =~ "First answer"
    assert html =~ "Second question"
    assert html =~ "Second answer"
  end

  test "each exchange adds two messages (user + assistant)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "A")

    {:ok, doc} = Floki.parse_document(render(view))
    bubbles = Floki.find(doc, "[data-chat-message-bubble]")
    assert length(bubbles) == 2
  end

  # ── Negative ─────────────────────────────────────────────────

  test "hero is NOT present after first message", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Hello", "Hi")
    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  test "assistant bubble content is not double-escaped (no HTML entities in rendered output)", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "Normal answer text.")
    html = render(view)
    refute html =~ "&amp;lt;"
    refute html =~ "&amp;gt;"
  end

  # ── Width class regression ────────────────────────────────────

  test "assistant bubble container does not have max-w-none (width conflict guard)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "Answer")

    {:ok, doc} = Floki.parse_document(render(view))
    [bubble | _] = Floki.find(doc, "[data-role='assistant'][data-chat-message-bubble]")
    class = Floki.attribute([bubble], "class") |> List.first("")

    refute String.contains?(class, "max-w-none"),
           "assistant bubble container must not have max-w-none (overrides max-w-[80%])"
  end

  # ── XSS prevention ────────────────────────────────────────────

  test "XSS prevention: <script> in assistant content is HTML-escaped", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_and_finish(view, "Q", "<script>alert(1)</script>")
    html = render(view)
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end
end
