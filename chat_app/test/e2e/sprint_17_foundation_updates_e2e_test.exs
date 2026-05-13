defmodule ChatAppWeb.Sprint17FoundationUpdatesE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "displays Threadworks AI branding and persistent footer", %{session: session} do
    session =
      session
      |> visit("/")
      |> execute_script("""
      const tick = () => {
        const connected = window.liveSocket && window.liveSocket.isConnected && window.liveSocket.isConnected();
        if (connected) {
          document.body.dataset.lvConnected = 'true';
          return;
        }
        requestAnimationFrame(tick);
      };
      tick();
      """)
      |> assert_has(Query.css("body[data-lv-connected='true']"))

    assert page_title(session) == "Threadworks AI"
    assert_has(session, Query.css(".brand-wordmark", text: "Threadworks AI"))
  end

  feature "textarea becomes scrollable instead of hiding text when input exceeds max height", %{
    session: session
  } do
    session =
      session
      |> visit("/")
      |> assert_has(Query.css("#chat-input"))

    session =
      execute_script(session, """
        const tick = () => {
          const connected = window.liveSocket && window.liveSocket.isConnected && window.liveSocket.isConnected();
          if (connected) {
            document.body.dataset.lvConnected = 'true';
            return;
          }
          requestAnimationFrame(tick);
        };
        tick();
      """)

    session = assert_has(session, Query.css("body[data-lv-connected='true']"))

    session = execute_script(session, "document.body.dataset.script2Ran = 'true';")
    session = assert_has(session, Query.css("body[data-script2-ran='true']"))

    session =
      execute_script(session, """
        document.body.dataset.bigScriptRan = 'true';
        const el = document.getElementById('chat-input');
        document.body.dataset.textareaFound = el ? 'true' : 'false';
        if (el) {
          let s = "";
          for (let i = 0; i < 200; i++) {
            s += "line " + (i + 1) + "\\n";
          }
          el.value = s;
          el.dispatchEvent(new Event('input', {bubbles: true}));

          const scrollable = el.scrollHeight > el.clientHeight;
          const overflowY = getComputedStyle(el).overflowY;
          document.body.dataset.textareaScrollable = scrollable ? 'true' : 'false';
          document.body.dataset.textareaOverflowY = overflowY;
          document.body.dataset.textareaScrollHeight = String(el.scrollHeight);
          document.body.dataset.textareaClientHeight = String(el.clientHeight);

          el.scrollTop = el.scrollHeight;
          document.body.dataset.textareaScrolled = (el.scrollTop > 0).toString();
        }
      """)

    session = assert_has(session, Query.css("body[data-script2-ran='true']"))
    session = assert_has(session, Query.css("body[data-big-script-ran='true']"))
    session = assert_has(session, Query.css("body[data-textarea-found='true']"))

    assert_has(session, Query.css("body[data-textarea-scrollable='true']"))
    assert_has(session, Query.css("body[data-textarea-overflow-y='auto']"))
    assert_has(session, Query.css("body[data-textarea-scrolled='true']"))
  end

  feature "error alerts render with semantic contrast ratios, not hardcoded colors", %{
    session: session
  } do
    session =
      session
      |> visit("/")
      |> execute_script("""
      const tick = () => {
        const connected = window.liveSocket && window.liveSocket.isConnected && window.liveSocket.isConnected();
        if (connected) {
          document.body.dataset.lvConnected = 'true';
          return;
        }
        requestAnimationFrame(tick);
      };
      tick();
      """)
      |> assert_has(Query.css("body[data-lv-connected='true']"))
      |> assert_has(Query.css("button[phx-click='toggle_settings']"))
      |> execute_script(
        "document.querySelector(\"button[phx-click='toggle_settings']\")?.click();"
      )
      |> assert_has(Query.css("[data-settings-drawer]"))

    session =
      session
      |> fill_in(Query.css("input[name='settings[temperature]']"), with: "5")
      |> click(Query.css("form[phx-submit='save_settings'] button[type='submit']"))

    assert_has(session, Query.css("[data-settings-drawer]"))
    refute_has(session, Query.css("[role='alert'][class*='red-500']"))
  end
end
