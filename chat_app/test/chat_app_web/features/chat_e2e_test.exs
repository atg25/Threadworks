defmodule ChatAppWeb.ChatE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  # Helper: submit the composer by clicking the send button.
  # Wallaby's fill_in/2 uses WebDriver's setValue which doesn't fire native
  # input events, so phx-change="update_input" doesn't update @input on the
  # server (the button stays disabled). We work around this by typing each
  # character with send_keys which fires keystroke events, OR by clicking the
  # send button directly after fill_in to bypass the @input-based disabled check.
  defp type_and_submit(session, text) do
    # Use send_keys/2 to type character-by-character. This fires real
    # keydown/keypress/keyup/input events that LiveView's phx-change="update_input"
    # picks up, updating @input on the server to enable the send button.
    # Then send_keys([:enter]) triggers ChatComposer.onKeyDown → requestSubmit().
    session
    |> click(css("#chat-input"))
    |> send_keys(text)
    |> send_keys([:enter])
  end

  # ── Page load ────────────────────────────────────────────────

  feature "home page loads and shows hero intro", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-homepage-chat-intro]"))
  end

  feature "page has a non-empty <title> element", %{session: session} do
    session = visit(session, "/")

    session =
      execute_script(session, """
        document.body.setAttribute('data-test-title',
          document.title && document.title.length > 0 ? 'set' : 'empty')
      """)

    assert_has(session, css("body[data-test-title='set']"))
  end

  feature "body does not have a vertical scrollbar (overflow hidden)", %{session: session} do
    session = visit(session, "/")

    session =
      execute_script(session, """
        document.body.setAttribute('data-test-overflow',
          getComputedStyle(document.body).overflow)
      """)

    assert_has(session, css("body[data-test-overflow*='hidden']"))
  end

  feature "section fills the full viewport height", %{session: session} do
    session = visit(session, "/")
    # Allow up to 8px tolerance for sub-pixel rounding in headless Chrome.
    session =
      execute_script(session, """
        const section = document.querySelector('[data-chat-surface]');
        const diff = Math.abs(section.getBoundingClientRect().height - window.innerHeight);
        section.setAttribute('data-test-height-diff', diff.toFixed(1));
        section.setAttribute('data-test-height-ok', diff < 8 ? 'true' : 'false');
      """)

    assert_has(session, css("[data-chat-surface][data-test-height-ok='true']"))
  end

  # ── Font loading ──────────────────────────────────────────────

  feature "IBM Plex Sans is applied to the body", %{session: session} do
    session = visit(session, "/")

    session =
      execute_script(session, """
        document.body.setAttribute('data-test-font',
          getComputedStyle(document.body).fontFamily)
      """)

    assert_has(session, css("body[data-test-font*='IBM Plex Sans']"))
  end

  # ── Hero section ──────────────────────────────────────────────

  feature "hero shows three service chips", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-homepage-service-chip]", count: 3))
  end

  feature "hero shows the correct heading text", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("h2", text: "One compact system for AI-assisted work"))
  end

  feature "hero shows three proof-point cards", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-homepage-proof-card]", count: 3))
  end

  # ── Composer ─────────────────────────────────────────────────

  feature "composer textarea is visible and focusable", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("#chat-input"))
    |> click(css("#chat-input"))
    |> assert_has(css("#chat-input:focus"))
  end

  feature "send button is enabled when composer is empty", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("button[aria-label='Send message']:not([disabled])"))
  end

  feature "send button becomes enabled when user types a message", %{session: session} do
    # Use send_keys to type so LiveView's phx-change fires.
    # Use assert_has(:not[disabled]) rather than refute_has([disabled]) because
    # assert_has polls until max_wait_time, while refute_has fails immediately.
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> send_keys("Hello AI")
    |> assert_has(css("button[aria-label='Send message']:not([disabled])"))
  end

  feature "textarea auto-resizes when text wraps multiple lines", %{session: session} do
    session = visit(session, "/")

    session =
      execute_script(session, """
        const el = document.getElementById('chat-input');
        el.setAttribute('data-initial-height', el.offsetHeight);
      """)

    # Use fill_in for speed then trigger input event manually so ChatComposer
    # hook fires its resize() listener.
    long_text = String.duplicate("word ", 50)

    session =
      session
      |> click(css("#chat-input"))
      |> fill_in(css("#chat-input"), with: long_text)

    session =
      execute_script(session, """
        const el = document.getElementById('chat-input');
        el.dispatchEvent(new Event('input', {bubbles: true}));
      """)

    session =
      execute_script(session, """
        const el = document.getElementById('chat-input');
        const initial = parseInt(el.getAttribute('data-initial-height') || '0');
        el.setAttribute('data-height-grew', el.offsetHeight > initial ? 'true' : 'false');
      """)

    assert_has(session, css("#chat-input[data-height-grew='true']"))
  end

  # ── Sending a message ─────────────────────────────────────────

  feature "sending a message hides the hero and shows user bubble", %{session: session} do
    session
    |> visit("/")
    |> type_and_submit("Hello AI")
    # Wait for the user bubble first (polls until max_wait_time);
    # once the bubble appears the hero is guaranteed gone.
    |> assert_has(css("[data-role='user']"))
    |> refute_has(css("[data-homepage-chat-intro]"))
  end

  feature "user bubble contains the sent message text", %{session: session} do
    session
    |> visit("/")
    |> type_and_submit("My test message")
    |> assert_has(css("[data-role='user']", text: "My test message"))
  end

  feature "composer clears after sending a message", %{session: session} do
    session =
      session
      |> visit("/")
      |> type_and_submit("Hello")

    # Wait for the LiveView to clear the input (hero gone = LiveView updated)
    session = assert_has(session, css("[data-role='user']"))

    session =
      execute_script(session, """
        const val = document.getElementById('chat-input').value;
        document.getElementById('chat-input').setAttribute(
          'data-test-value', val === '' ? 'empty' : 'not-empty');
      """)

    assert_has(session, css("#chat-input[data-test-value='empty']"))
  end

  feature "assistant bubble appears after stream completes", %{session: session} do
    # E2EStub sends tokens immediately; max_wait_time: 3000 handles timing
    session
    |> visit("/")
    |> type_and_submit("Hello")
    |> assert_has(css("[data-role='assistant']"))
  end

  feature "assistant bubble contains the stub response text", %{session: session} do
    session
    |> visit("/")
    |> type_and_submit("Hello")
    |> assert_has(css("[data-role='assistant']", text: "Stub response."))
  end

  # ── Shift+Enter inserts newline (does NOT submit) ─────────────

  feature "Shift+Enter inserts a newline and does NOT submit", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Line one")
    |> send_keys([:shift, :enter])
    # Hero should still be visible (message was not sent)
    |> assert_has(css("[data-homepage-chat-intro]"))
  end

  # ── Empty submit no-op ────────────────────────────────────────

  feature "pressing Enter with empty composer does nothing", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> send_keys([:enter])
    # Hero still present — no message was sent
    |> assert_has(css("[data-homepage-chat-intro]"))
  end

  # ── Multiple exchanges ────────────────────────────────────────

  feature "sending two messages shows four bubbles total", %{session: session} do
    session
    |> visit("/")
    |> type_and_submit("First")
    # Wait for the assistant response from E2EStub before sending the second message
    |> assert_has(css("[data-role='assistant']"))
    |> type_and_submit("Second")
    # 2 user + 2 assistant = 4 total
    |> assert_has(css("[data-chat-message-bubble]", count: 4))
  end

  # ── Scroll pill ───────────────────────────────────────────────

  feature "scroll-to-bottom pill starts hidden", %{session: session} do
    session
    |> visit("/")
    |> refute_has(css("#scroll-cta-dock:not(.hidden)"))
  end

  feature "scroll pill appears after user scrolls up in a long conversation", %{session: session} do
    # Build enough messages (8 exchanges = 16 bubbles) to guarantee overflow.
    session =
      Enum.reduce(1..8, visit(session, "/"), fn i, s ->
        s
        |> type_and_submit("Question #{i}")
        |> assert_has(css("[data-chat-message-bubble]", minimum: i * 2))
      end)

    # Force scroll to bottom first (ChatScroll hook does this on update,
    # but let's be explicit), then scroll to top so there's definitely overflow.
    session =
      execute_script(session, """
        const vp = document.getElementById('chat-viewport');
        vp.scrollTop = vp.scrollHeight;
      """)

    session =
      execute_script(session, """
        const vp = document.getElementById('chat-viewport');
        vp.scrollTop = 0;
        vp.dispatchEvent(new Event('scroll', {bubbles: true}));
      """)

    # The ChatScroll hook directly toggles .hidden on #scroll-cta-dock
    # via client-side JS (no server round-trip needed).
    assert_has(session, css("#scroll-cta-dock:not(.hidden)"))
  end

  feature "scroll pill hides again when user scrolls back to the bottom", %{session: session} do
    # Build overflow (8 exchanges = 16 bubbles).
    session =
      Enum.reduce(1..8, visit(session, "/"), fn i, s ->
        s
        |> type_and_submit("Question #{i}")
        |> assert_has(css("[data-chat-message-bubble]", minimum: i * 2))
      end)

    # Scroll to top → pill becomes visible.
    session =
      execute_script(session, """
        const vp = document.getElementById('chat-viewport');
        vp.scrollTop = 0;
        vp.dispatchEvent(new Event('scroll', {bubbles: true}));
      """)

    session = assert_has(session, css("#scroll-cta-dock:not(.hidden)"))

    # Scroll back to bottom → ChatScroll.onScroll sets isAtBottom = true
    # and toggles .hidden back on.
    session =
      execute_script(session, """
        const vp = document.getElementById('chat-viewport');
        vp.scrollTop = vp.scrollHeight;
        vp.dispatchEvent(new Event('scroll', {bubbles: true}));
      """)

    refute_has(session, css("#scroll-cta-dock:not(.hidden)"))
  end

  # ── CSS classes present ───────────────────────────────────────

  feature "root section has grid class", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-chat-surface].grid"))
  end

  feature "header has glassmorphism class ui-chat-header-surface", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-chat-surface-header].ui-chat-header-surface"))
  end

  feature "composer plane class is present", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css(".ui-chat-composer-plane"))
  end

  feature "composer frame class is present", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css(".ui-chat-composer-frame"))
  end
end
