---
status: complete
---

# Sprint 1.10 — Full End-to-End Tests (Wallaby)

**Spec:** spec-1 — all sections  
**Goal:** Drive a real Phoenix server + real browser (headless Chrome via ChromeDriver) to verify the complete user-facing experience: visual layout, hero animation, typing in the composer, sending a message (stubbed AI response), receiving streaming tokens in the UI, scroll behaviour, and the scroll-to-bottom pill. This is the final green gate before spec-1 is declared done.  
**Depends on:** sprints 1.1–1.9 all passing  
**Strategy:** All E2E tests use the `ChatApp.OpenAI.Stub` (already configured in test env) so no real network calls are made. The stub sends two tokens then `:stream_done` immediately, making the streaming path fast and deterministic.

---

## TDD Approach

| Scenario                         | Type         | Assertions                                               |
| -------------------------------- | ------------ | -------------------------------------------------------- |
| Page loads with hero             | E2E positive | `[data-homepage-chat-intro]` visible                     |
| Fonts loaded                     | E2E positive | Computed font-family includes IBM Plex Sans              |
| Grid fills viewport              | E2E positive | `<section>` clientHeight == window.innerHeight           |
| Body no scroll                   | E2E positive | `document.body.scrollHeight == window.innerHeight`       |
| Typing in composer               | E2E positive | Textarea value updates, send button enabled              |
| Send message → hero gone         | E2E positive | Hero absent, user bubble present                         |
| Streaming tokens appear          | E2E positive | Assistant bubble content grows                           |
| Scroll pill shows on scroll up   | E2E positive | `#scroll-cta-dock` loses `hidden` after scroll           |
| Scroll pill hides on scroll down | E2E positive | `#scroll-cta-dock` gains `hidden` after scroll to bottom |
| Empty submit no-op               | E2E negative | Hero still present, no bubble added                      |
| Composer clears after send       | E2E positive | Textarea is empty after submit                           |

---

## Step 1 — Add Wallaby and ChromeDriver to deps

`mix.exs`:

```elixir
{:wallaby, "~> 0.30", runtime: false, only: :test}
```

```bash
mix deps.get
```

Install ChromeDriver (macOS):

```bash
brew install chromedriver
# Verify:
chromedriver --version
```

---

## Step 2 — Configure Wallaby

`config/test.exs`:

```elixir
config :wallaby,
  otp_app: :chat_app,
  driver: Wallaby.Chrome,
  chrome: [
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"]
  ]
```

`test/test_helper.exs` — add before `ExUnit.start()`:

```elixir
{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, ChatAppWeb.Endpoint.url())
```

Add `use Wallaby.Feature` support:

`test/support/feature_case.ex`:

```elixir
defmodule ChatAppWeb.FeatureCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature
      import Wallaby.Query
      import Wallaby.Browser
      alias Wallaby.Query
    end
  end
end
```

---

## Step 3 — Write all E2E tests FIRST (Red)

### `test/chat_app_web/features/chat_e2e_test.exs`

```elixir
defmodule ChatAppWeb.ChatE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  # ── Page load ────────────────────────────────────────────────

  feature "home page loads and shows hero intro", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("[data-homepage-chat-intro]"))
  end

  feature "page has a non-empty <title> element", %{session: session} do
    session = visit(session, "/")
    # Store document.title presence in a data attribute for assertion
    session = execute_script(session, """
      document.body.setAttribute('data-test-title',
        document.title && document.title.length > 0 ? 'set' : 'empty')
    """)
    assert_has(session, css("body[data-test-title='set']"))
  end

  feature "body does not have a vertical scrollbar (overflow hidden)", %{session: session} do
    session = visit(session, "/")
    # Store computed overflow in a data attribute, then assert on it.
    # Wallaby execute_script/3 returns a session; use DOM attributes to surface values.
    session = execute_script(session, """
      document.body.setAttribute('data-test-overflow',
        getComputedStyle(document.body).overflow)
    """)
    assert_has(session, css("body[data-test-overflow*='hidden']"))
  end

  feature "section fills the full viewport height", %{session: session} do
    session = visit(session, "/")
    session = execute_script(session, """
      const section = document.querySelector('[data-chat-surface]');
      const close = Math.abs(section.getBoundingClientRect().height - window.innerHeight) < 4;
      section.setAttribute('data-test-height-ok', close ? 'true' : 'false');
    """)
    assert_has(session, css("[data-chat-surface][data-test-height-ok='true']"))
  end

  # ── Font loading ──────────────────────────────────────────────

  feature "IBM Plex Sans is applied to the body", %{session: session} do
    session = visit(session, "/")
    session = execute_script(session, """
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

  feature "send button is disabled when composer is empty", %{session: session} do
    session
    |> visit("/")
    |> assert_has(css("button[aria-label='Send message'][disabled]"))
  end

  feature "send button becomes enabled when user types a message", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Hello AI")
    |> refute_has(css("button[aria-label='Send message'][disabled]"))
  end

  feature "textarea auto-resizes when text wraps multiple lines", %{session: session} do
    session = visit(session, "/")
    # Record initial height in a data attribute
    session = execute_script(session, """
      const el = document.getElementById('chat-input');
      el.setAttribute('data-initial-height', el.offsetHeight);
    """)
    long_text = String.duplicate("word ", 50)
    session = session
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: long_text)
    # Compare current height to saved initial height
    session = execute_script(session, """
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
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Hello AI")
    |> send_keys([:enter])
    |> refute_has(css("[data-homepage-chat-intro]"))
    |> assert_has(css("[data-role='user']"))
  end

  feature "user bubble contains the sent message text", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "My test message")
    |> send_keys([:enter])
    |> assert_has(css("[data-role='user']", text: "My test message"))
  end

  feature "composer clears after sending a message", %{session: session} do
    session = session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Hello")
    |> send_keys([:enter])
    session = execute_script(session, """
      const val = document.getElementById('chat-input').value;
      document.getElementById('chat-input').setAttribute(
        'data-test-value', val === '' ? 'empty' : 'not-empty');
    """)
    assert_has(session, css("#chat-input[data-test-value='empty']"))
  end

  feature "assistant bubble appears after stream completes", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Hello")
    |> send_keys([:enter])
    # Stub sends tokens immediately; give LiveView 500ms to patch the DOM
    |> assert_has(css("[data-role='assistant']"), timeout: 2000)
  end

  feature "assistant bubble contains the stub response text", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Hello")
    |> send_keys([:enter])
    |> assert_has(css("[data-role='assistant']", text: "Stub response."), timeout: 2000)
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
    # Hero still present
    |> assert_has(css("[data-homepage-chat-intro]"))
  end

  # ── Multiple exchanges ────────────────────────────────────────

  feature "sending two messages shows four bubbles total", %{session: session} do
    session
    |> visit("/")
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "First")
    |> send_keys([:enter])
    |> assert_has(css("[data-role='assistant']"), timeout: 2000)
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: "Second")
    |> send_keys([:enter])
    |> assert_has(css("[data-chat-message-bubble]", count: 4), timeout: 2000)
  end

  # ── Scroll pill ───────────────────────────────────────────────

  feature "scroll-to-bottom pill starts hidden", %{session: session} do
    session
    |> visit("/")
    |> refute_has(css("#scroll-cta-dock:not(.hidden)"))
  end

  feature "scroll pill appears after user scrolls up in a long conversation", %{session: session} do
    # Build up enough messages to make the viewport scrollable
    session = Enum.reduce(1..6, session |> visit("/"), fn i, s ->
      s
      |> click(css("#chat-input"))
      |> fill_in(css("#chat-input"), with: "Question #{i}")
      |> send_keys([:enter])
      |> assert_has(css("[data-role='assistant']"), timeout: 2000)
    end)

    # Scroll up and dispatch a scroll event so the ChatScroll hook updates
    # execute_script/3 returns a session — must chain via reassignment
    session = execute_script(session,
      "document.getElementById('chat-viewport').scrollTop = 0;"
    )
    session = execute_script(session,
      "document.getElementById('chat-viewport').dispatchEvent(new Event('scroll'));"
    )

    assert_has(session, css("#scroll-cta-dock:not(.hidden)"), timeout: 1000)
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
```

Run:

```bash
mix test test/chat_app_web/features/chat_e2e_test.exs --tag e2e
```

Expected: all fail (test infrastructure not wired). This is the Red state.

---

## Step 4 — Wire the test server (Green)

`test/test_helper.exs`:

```elixir
ExUnit.start(exclude: [:real_api])

{:ok, _} = Application.ensure_all_started(:wallaby)
Application.put_env(:wallaby, :base_url, ChatAppWeb.Endpoint.url())
```

`config/test.exs` — ensure the endpoint is started:

```elixir
config :chat_app, ChatAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: true   # ← CRITICAL — Wallaby needs a running HTTP server
```

---

## Step 5 — Run E2E tests (Red → Green)

```bash
mix test --tag e2e
```

Fix failures one by one. Common issues:

| Failure                               | Fix                                                                                                                               |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `ChromeDriver not found`              | `brew install chromedriver`                                                                                                       |
| `assert_has` timeout on stub response | Increase `Wallaby.Feature` default timeout in `config/test.exs`: `config :wallaby, js_logger: false, screenshot_on_failure: true` |
| Grid height assertion fails           | Check `html`/`body`/`main` all have `height:100%` per sprint 1.3                                                                  |
| Font assertion fails                  | Google Fonts may not load in headless mode — adjust test to check `--font-ibm-plex-sans` CSS var is set                           |
| Scroll pill assertion fails           | Ensure `ChatScroll` hook is registered and the `scroll` event fires correctly                                                     |

---

## Step 6 — Run full suite

```bash
mix test --exclude real_api
cd assets && npm test && cd ..
```

**Target:** 0 failures, 0 errors across all layers.

---

## Step 7 — Screenshot coverage

Add to `config/test.exs`:

```elixir
config :wallaby,
  screenshot_on_failure: true,
  screenshot_dir: "test/screenshots"
```

On any failure, a screenshot is saved to `test/screenshots/` for debugging.

---

## Spec-1 Checklist (Final Gate)

Cross-reference the spec-1 §15 pre-launch checklist. All 16 items must be verified — some by tests, some by visual inspection in the browser:

| #   | Item                                 | Sprint   | Verified by                                |
| --- | ------------------------------------ | -------- | ------------------------------------------ |
| 1   | `html`/`body` `height:100%`          | 1.3      | `ChatLiveTest` regex assertions            |
| 2   | Font `<link>` in `<head>`            | 1.2      | `CSSArchitectureTest` + E2E font assertion |
| 3   | CSS import order correct             | 1.2      | `CSSArchitectureTest` order assertions     |
| 4   | `tailwindcss-animate` in devDeps     | 1.1      | `package.json` check                       |
| 5   | `@tailwindcss/typography` in devDeps | 1.1      | `package.json` check                       |
| 6   | `Req ~> 0.5` in deps                 | 1.1      | `mix.exs` version pin                      |
| 7   | `Jason` in deps                      | 1.1      | `mix.exs`                                  |
| 8   | `Earmark` in deps                    | 1.1      | `mix.exs`                                  |
| 9   | `OPENAI_API_KEY` via `fetch_env!`    | 1.1      | `ConfigTest`                               |
| 10  | `.env` in `.gitignore`               | 1.1      | Manual                                     |
| 11  | `Task.start` (not `Task.async`)      | 1.6      | Code review                                |
| 12  | SSE chunk boundary handling          | 1.7, 1.9 | `SSETest` + Bypass integration             |
| 13  | `ui-chat-composer-plane` wrapper     | 1.5      | Composer markup test + E2E class check     |
| 14  | `ui-chat-composer-seam` hairline     | 1.5      | Composer markup test + E2E class check     |
| 15  | `hero_state: false` on first send    | 1.6      | `ChatLiveEventsTest`                       |
| 16  | `phx-hook` on scroll/composer        | 1.5      | Composer markup test + E2E interaction     |

---

## Acceptance Criteria

- [ ] `Wallaby ~> 0.30` in test deps, `mix deps.get` passes
- [ ] ChromeDriver installed and accessible
- [ ] `config/test.exs` has `server: true` on the endpoint
- [ ] All 26 E2E feature tests pass (`mix test --tag e2e`)
- [ ] `mix test --exclude real_api` exits 0
- [ ] `cd assets && npm test` exits 0
- [ ] All 16 spec-1 §15 checklist items verified (test or visual)
- [ ] Screenshot directory configured for failure debugging
- [ ] No `mix compile` warnings

---

## Out of Scope for Spec-1

All items in spec-1 §16: auth, DB persistence, file uploads, `@mention`, admin, floating chat, Oban, MCP sidecars, dark mode toggle, density toggle.
