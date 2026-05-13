defmodule ChatAppWeb.Sprint20MultiThemeE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "visual theme updates immediately and persists across reloads", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("[data-phx-theme='swiss']"))
      |> execute_script("""
      (() => {
        const root = document.documentElement;
        const persisted = localStorage.getItem('chat_app:theme') === 'swiss';
        const applied = root.dataset.theme === 'swiss' && root.classList.contains('theme-swiss');
        document.body.dataset.sprint20ThemePersisted = persisted && applied ? 'true' : 'false';
      })();
      """)

    assert_has(session, Query.css("body[data-sprint20-theme-persisted='true']"))

    session =
      session
      |> visit("/")
      |> execute_script("""
      (() => {
        const root = document.documentElement;
        const hydrated = localStorage.getItem('chat_app:theme') === 'swiss' &&
          root.dataset.theme === 'swiss' &&
          root.classList.contains('theme-swiss');
        document.body.dataset.sprint20ThemeHydrated = hydrated ? 'true' : 'false';
      })();
      """)

    assert_has(session, Query.css("body[data-sprint20-theme-hydrated='true']"))
  end

  feature "LiveView patches do not overwrite JS-managed theme attributes", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("[data-phx-theme='swiss']"))
      |> fill_in(Query.css("#chat-input"), with: "Trigger a LiveView patch.")
      |> send_keys([:enter])
      |> assert_has(Query.css("[data-chat-message-role='assistant']", text: "Stub response."))
      |> execute_script("""
      (() => {
        const root = document.documentElement;
        const activeButton = document.querySelector("[data-phx-theme='swiss']");
        const persisted = localStorage.getItem('chat_app:theme') === 'swiss';
        const themed = root.dataset.theme === 'swiss' && root.classList.contains('theme-swiss');
        const pressed = activeButton?.getAttribute('aria-pressed') === 'true';
        document.body.dataset.sprint20ThemePatchSafe = persisted && themed && pressed ? 'true' : 'false';
      })();
      """)

    assert_has(session, Query.css("body[data-sprint20-theme-patch-safe='true']"))
  end

  feature "rapid theme switching keeps one active state without console errors", %{
    session: session
  } do
    session =
      session
      |> visit("/")
      |> execute_script("""
      (() => {
        const errors = [];
        const originalError = console.error;
        console.error = (...args) => {
          errors.push(args.map(String).join(" "));
          originalError.apply(console, args);
        };

        try {
          const buttons = Array.from(document.querySelectorAll("[data-phx-theme]"));
          ["swiss", "mid-century", "techno-brutalist", "editorial", "swiss"].forEach((theme) => {
            document.querySelector(`[data-phx-theme='${theme}']`)?.click();
          });

          const activeButtons = buttons.filter((button) => button.getAttribute("aria-pressed") === "true");
          const root = document.documentElement;
          const activeStateStable =
            activeButtons.length === 1 &&
            activeButtons[0]?.dataset.phxTheme === "swiss" &&
            root.dataset.theme === "swiss" &&
            root.classList.contains("theme-swiss") &&
            localStorage.getItem("chat_app:theme") === "swiss";

          document.body.dataset.sprint20RapidThemeOk =
            errors.length === 0 && activeStateStable ? "true" : "false";
        } catch (_error) {
          document.body.dataset.sprint20RapidThemeOk = "false";
        } finally {
          console.error = originalError;
        }
      })();
      """)

    assert_has(session, Query.css("body[data-sprint20-rapid-theme-ok='true']"))
  end
end
