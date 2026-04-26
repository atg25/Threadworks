---
status: complete
---

# Sprint 1.3 — Root Layout, Height Propagation & Page Grid

**Spec:** spec-1 §4, §5  
**Goal:** Wire the `"/"` route to `ChatLive`, update `root.html.heex` and the app layout wrapper (`app.html.heex` or `Layouts.app/1`, depending on scaffold) so `html`/`body`/`main` all propagate 100% height, and render the three-row CSS grid section (header + viewport + composer rows as empty placeholders). The page must fill the full viewport without any page-level scroll.  
**Depends on:** sprint-1.1 (project scaffolded), sprint-1.2 (CSS compiled)  
**Delivers:** `GET /` renders a `ChatLive` page with the 3-row grid visible in the browser. All layout tests pass.

---

## TDD Approach

| Layer           | Tool                           | Assertions                                                   |
| --------------- | ------------------------------ | ------------------------------------------------------------ |
| Route existence | `Phoenix.ConnTest`             | `GET /` returns 200                                          |
| LiveView mount  | `Phoenix.LiveViewTest`         | LiveView process starts, assigns populated                   |
| Grid markup     | `Phoenix.LiveViewTest` + Floki | `<section>` has correct grid classes, three children present |
| Height attrs    | `Phoenix.LiveViewTest` + Floki | `<html style>` and `<body style>` contain `height:100%`      |
| No page scroll  | Wallaby E2E (sprint 1.10)      | `document.body.scrollHeight == window.innerHeight`           |

---

## Step 1 — Write tests FIRST (Red)

### `test/chat_app_web/live/chat_live_test.exs`

Create this file before writing a single line of `ChatLive`.

```elixir
defmodule ChatAppWeb.ChatLiveTest do
  use ChatAppWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # ── Route ──────────────────────────────────────────────────────

  # Positive: root path is live
  test "GET / mounts ChatLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface"
  end

  # Negative: non-live route is gone
  test "GET / does not render the default Phoenix welcome page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    refute html =~ "Peace of mind from prototype to production"
  end

  # ── Initial assigns ────────────────────────────────────────────

  test "ChatLive mounts with hero_state true", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "ChatLive mounts with empty messages list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # No message bubbles on mount
    refute has_element?(view, "[data-chat-message-bubble]")
  end

  test "ChatLive mounts with is_sending false (send button enabled)", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    # Send button should exist and not be disabled at mount (no input though)
    assert has_element?(view, "button[aria-label='Send message']")
  end

  # ── Grid markup ────────────────────────────────────────────────

  test "root section has 3-row grid classes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "grid-rows-[auto_minmax(0,1fr)_auto]"
  end

  test "root section has data-chat-surface attribute", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface"
  end

  test "header row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-surface-header"
  end

  test "message viewport row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-message-region"
  end

  test "composer row is rendered", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "data-chat-bottom-rail"
  end

  # ── Height propagation ─────────────────────────────────────────

  test "root layout html element has height:100% style", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/html[^>]+style=[^>]*height:\s*100%/
  end

  test "root layout body element has height:100% style", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/body[^>]+style=[^>]*height:\s*100%/
  end

  test "body has overflow:hidden style", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ ~r/body[^>]+style=[^>]*overflow:\s*hidden/
  end

  # ── Negative ───────────────────────────────────────────────────

  test "page does not contain a scrollable body (overflow is hidden)", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    # body must NOT have overflow:auto or overflow:scroll
    refute html =~ ~r/body[^>]+style=[^>]*overflow:\s*(auto|scroll)/
  end

  test "section does not use flex-col alone (must be grid)", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    # The outer section is a grid, not just a flex container
    assert html =~ ~r/class="[^"]*\bgrid\b[^"]*"/
  end
end
```

Run:

```bash
mix test test/chat_app_web/live/chat_live_test.exs
```

Expected: **all tests fail** — `ChatLive` does not exist yet. This is correct Red state.

---

## Step 2 — Update the router (Green starts here)

`lib/chat_app_web/router.ex` — replace the `scope "/"` block:

```elixir
scope "/", ChatAppWeb do
  pipe_through :browser

  live "/", ChatLive, :index
end
```

Remove any existing `get "/"` controller route.

---

## Step 3 — Create `ChatLive` (minimal scaffold for layout tests)

`lib/chat_app_web/live/chat_live.ex`:

```elixir
defmodule ChatAppWeb.ChatLive do
  use ChatAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       messages:      [],
       input:         "",
       is_sending:    false,
       stream_buffer: "",
       at_bottom:     true,
       hero_state:    true
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      data-chat-surface="true"
      data-chat-surface-mode="embedded"
      class="relative grid h-full min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)_auto] bg-background">

      <%!-- Row 1: Header (decorative in spec-1) --%>
      <div class="ui-chat-header-surface relative z-20 flex shrink-0 items-center
                  justify-end border-b border-[--border-color] px-[--space-3] py-[--space-2]"
           data-chat-surface-header="true"
           data-chat-surface-header-mode="embedded">
      </div>

      <%!-- Row 2: Message Viewport (placeholder — filled in sprint 1.4 / 1.8) --%>
      <div class="relative flex h-full min-h-0 w-full flex-col overflow-hidden"
           data-chat-message-region="true">
      </div>

      <%!-- Row 3: Composer Plane (placeholder — filled in sprint 1.5) --%>
      <div class="flex flex-col gap-[--space-2]" data-chat-bottom-rail="true">
      </div>

    </section>
    """
  end
end
```

---

## Step 4 — Update `root.html.heex`

`lib/chat_app_web/components/layouts/root.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en" class="" style="height:100%; overflow-x:hidden;">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />

    <%!-- Google Fonts --%>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,560;1,9..144,400&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />

    <link rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}></script>
  </head>

  <body class="bg-background text-foreground" style="height:100%; overflow:hidden;">
    <%= @inner_content %>
  </body>
</html>
```

---

## Step 5 — Update app layout wrapper

Phoenix 1.7 scaffolds may define the app layout in `lib/chat_app_web/components/layouts.ex` via `def app(assigns)` instead of `lib/chat_app_web/components/layouts/app.html.heex`. Update whichever pattern your project uses.

If your project has `app.html.heex`:

`lib/chat_app_web/components/layouts/app.html.heex`:

```heex
<main class="h-full w-full overflow-hidden" style="height:100%;">
  <%= @inner_content %>
</main>
```

---

## Step 6 — Run tests (Red → Green)

```bash
mix test test/chat_app_web/live/chat_live_test.exs
```

All 15 tests should pass. Common failures and fixes:

| Failure                              | Fix                                                                                |
| ------------------------------------ | ---------------------------------------------------------------------------------- |
| `data-chat-surface` not found        | Check `ChatLive.render/1` — the attribute must be on the `<section>`               |
| `grid-rows-[...]` not in HTML        | Tailwind classes are in the HTML even if not compiled to CSS yet                   |
| `height:100%` regex fails            | Check `root.html.heex` — style attr must be on the `<html>` tag, not just `<body>` |
| `data-homepage-chat-intro` not found | Hero component not yet added — add a placeholder div with that attr temporarily    |

For the `data-homepage-chat-intro` test, temporarily add this to the viewport row in `ChatLive`:

```heex
<div data-homepage-chat-intro="true" :if={@hero_state}></div>
```

This placeholder will be replaced with the real hero component in sprint 1.4.

---

## Step 7 — Run full suite

```bash
mix test
```

Sprint 1.1 and 1.2 tests still pass. The new ChatLive tests all pass. Total: ~33 tests.

---

## Acceptance Criteria

- [ ] `live "/", ChatLive, :index` wired in router
- [ ] `GET /` returns HTTP 200 via LiveView
- [ ] All 15 `ChatLiveTest` layout tests pass
- [ ] `<html>` has `style="height:100%"` in rendered output
- [ ] `<body>` has `style="height:100%; overflow:hidden;"` in rendered output
- [ ] `<section>` has `grid-rows-[auto_minmax(0,1fr)_auto]` class
- [ ] `data-chat-surface-header`, `data-chat-message-region`, `data-chat-bottom-rail` all present
- [ ] `mix test` exits 0

---

## Out of Scope for This Sprint

- Hero intro content (sprint 1.4)
- Composer markup and JS hooks (sprint 1.5)
- Event handlers (sprint 1.6)
- Any streaming or AI integration
