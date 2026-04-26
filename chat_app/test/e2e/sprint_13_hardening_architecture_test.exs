defmodule ChatAppWeb.Sprint13HardeningArchitectureE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  import ExUnit.CaptureLog

  @moduletag :e2e

  defp type_and_submit(session, text) do
    session
    |> click(css("#chat-input"))
    |> send_keys(text)
    |> send_keys([:enter])
  end

  feature "Positive — scroll-to-bottom pill works on first click", %{session: session} do
    session =
      session
      |> visit("/")
      |> type_and_submit("Hello")
      |> assert_has(css("[data-role='assistant']"))

    session =
      execute_script(session, """
        const viewport = document.getElementById('chat-viewport');
        const stack = viewport.querySelector('[data-chat-message-stack]');
        if (!document.getElementById('test-spacer')) {
          const spacer = document.createElement('div');
          spacer.id = 'test-spacer';
          spacer.style.height = '2000px';
          stack.prepend(spacer);
        }

        viewport.scrollTop = 0;
      """)

    session =
      execute_script(session, """
        document.getElementById('scroll-to-bottom').click();
      """)

    session =
      execute_script(session, """
        const viewport = document.getElementById('chat-viewport');
        const max = viewport.scrollHeight - viewport.clientHeight;
        const ok = Math.abs(viewport.scrollTop - max) < 8;
        viewport.setAttribute('data-test-at-bottom', ok ? 'true' : 'false');
      """)

    assert_has(session, css("#chat-viewport[data-test-at-bottom='true']"))
  end

  feature "Negative — pill is hidden on initial mount when at bottom", %{session: session} do
    session =
      session
      |> visit("/")
      |> execute_script("""
        const dock = document.getElementById('scroll-cta-dock');
        const exists = !!dock;
        const hiddenClass = exists && dock.classList.contains('hidden');
        const hiddenDisplay = exists && getComputedStyle(dock).display === 'none';

        document.body.setAttribute('data-dock-exists', exists ? 'true' : 'false');
        document.body.setAttribute('data-dock-hidden-class', hiddenClass ? 'true' : 'false');
        document.body.setAttribute('data-dock-hidden-display', hiddenDisplay ? 'true' : 'false');
      """)

    assert_has(session, css("body[data-dock-exists='true']"))

    assert_has(
      session,
      css("body[data-dock-hidden-class='true'][data-dock-hidden-display='true']")
    )
  end

  feature "Negative — repeated scroll events do not multiply click handlers", %{session: session} do
    session =
      session
      |> visit("/")
      |> type_and_submit("Hello")
      |> assert_has(css("[data-role='assistant']"))

    # Track additional click-listener attachments during scroll handling.
    session =
      execute_script(session, """
        const btn = document.getElementById('scroll-to-bottom');
        window.__extraScrollClickAdds = 0;

        const original = btn.addEventListener.bind(btn);
        btn.addEventListener = function(type, listener, options) {
          if (type === 'click') {
            window.__extraScrollClickAdds += 1;
          }

          return original(type, listener, options);
        };
      """)

    session =
      execute_script(session, """
        const viewport = document.getElementById('chat-viewport');
        const stack = viewport.querySelector('[data-chat-message-stack]');
        if (!document.getElementById('test-spacer')) {
          const spacer = document.createElement('div');
          spacer.id = 'test-spacer';
          spacer.style.height = '2000px';
          stack.prepend(spacer);
        }

        for (let i = 0; i < 5; i++) {
          viewport.scrollTop = 0;
          viewport.dispatchEvent(new Event('scroll', { bubbles: true }));
          viewport.scrollTop = viewport.scrollHeight;
          viewport.dispatchEvent(new Event('scroll', { bubbles: true }));
        }

        // Leave viewport away from bottom so dock should be visible.
        viewport.scrollTop = 0;
        viewport.dispatchEvent(new Event('scroll', { bubbles: true }));

        document.body.setAttribute(
          'data-extra-scroll-click-adds',
          String(window.__extraScrollClickAdds || 0)
        );
      """)

    session = assert_has(session, css("body[data-extra-scroll-click-adds='0']"))

    session = assert_has(session, css("#scroll-cta-dock:not(.hidden)"))
    session = click(session, css("#scroll-to-bottom"))

    session =
      execute_script(session, """
        const viewport = document.getElementById('chat-viewport');
        const max = viewport.scrollHeight - viewport.clientHeight;
        const ok = Math.abs(viewport.scrollTop - max) < 8;
        viewport.setAttribute('data-test-at-bottom', ok ? 'true' : 'false');
      """)

    assert_has(session, css("#chat-viewport[data-test-at-bottom='true']"))
  end

  feature "Negative — non-2xx surfaces a user-visible error AND emits a Logger entry", %{
    session: session
  } do
    bypass = Bypass.open()

    original_module = Application.get_env(:chat_app, :openai_module)
    original_url = Application.get_env(:chat_app, :openai_api_url)
    original_req_opts = Application.get_env(:chat_app, :req_options)

    on_exit(fn ->
      if original_module do
        Application.put_env(:chat_app, :openai_module, original_module)
      else
        Application.delete_env(:chat_app, :openai_module)
      end

      if original_url do
        Application.put_env(:chat_app, :openai_api_url, original_url)
      else
        Application.delete_env(:chat_app, :openai_api_url)
      end

      if original_req_opts do
        Application.put_env(:chat_app, :req_options, original_req_opts)
      else
        Application.delete_env(:chat_app, :req_options)
      end
    end)

    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

    Application.put_env(:chat_app, :req_options, [])

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Invalid API key"}}))
    end)

    log =
      capture_log(fn ->
        _session =
          session
          |> visit("/")
          |> type_and_submit("Hello")
          |> assert_has(css("[data-chat-message-error]", text: "HTTP 401"))
      end)

    assert log =~ "status: 401"
  end
end
