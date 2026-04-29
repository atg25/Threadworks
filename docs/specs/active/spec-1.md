# Spec 1 — Chat Console (Elixir / Phoenix LiveView)

**Goal:** Replicate the home-page chat UX of `ai_mcp_chat_ordo` as a working Phoenix LiveView app — visually and behaviourally identical to the original.  
**Scope:** Home page (`/`) only. Anonymous session. In-memory conversation state. No auth, no DB, no file uploads, no admin, no jobs queue.

---

## 0. Implementation Status (audit 2026-04-24)

> This section was added by an audit pass on **2026-04-24** after sprints 1.1–1.10 were marked complete. It is **descriptive**, not prescriptive — it records what was actually built and where the build diverged from the spec below. The drift items it lists are either (a) intentional improvements beyond the spec, or (b) defects in the spec text itself that the implementation correctly worked around or that follow-on Phase 2 sprints will fix. **Do not delete drift entries to "clean up" the spec — they are the change log.**

### 0.1 Verdict

**Status: shipped, with known drift.** Every section of this spec has at least one completed sprint that delivered the prescribed surface, and every item on the §15 checklist is satisfied in code. **SPRINT-11 (2026-04-25)** replaced the worst `escape: false`, hardcoded-model, and invalid-`<textarea>` patterns. **SPRINT-12 (2026-04-25)** replaced unsupervised stream tasks (§17 C-1) with a supervised `Task.Supervisor` + cancel-on-terminate, moved stream errors out of the OpenAI `messages` list (C-3), added per-session rate limiting, and removed scaffold dead code. **`tailwind.config.js` drift (D-1) remains** as called out in §17. The spec narrative is **not** the sole target for implementation — see §0.4, §17, and the Phase 2 sprint files.

### 0.2 Section → sprint map

| Spec section             | Topic                                                            | Delivered by                                                                                                       | Status                                                                                                                |
| ------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| §1 Stack                 | Dependency pins                                                  | sprint-1.1                                                                                                         | ✅ delivered                                                                                                          |
| §2 Fonts                 | Google Fonts wiring + CSS vars                                   | sprint-1.2                                                                                                         | ✅ delivered                                                                                                          |
| §3 CSS Architecture      | Copied CSS files + import order                                  | sprint-1.2                                                                                                         | ✅ delivered (with tooling drift — see §17 D-1)                                                                       |
| §4 Root Layout / Height  | `html`/`body`/`main` height: 100%                                | sprint-1.3                                                                                                         | ✅ delivered                                                                                                          |
| §5 Page Layout           | 3-row grid `<section>`                                           | sprint-1.3                                                                                                         | ✅ delivered                                                                                                          |
| §6.1 Header              | Decorative `ui-chat-header-surface`                              | sprint-1.3                                                                                                         | ✅ delivered                                                                                                          |
| §6.2 Message Viewport    | Glow + transcript + scroll pill                                  | sprint-1.4 (hero), sprint-1.5 (pill), sprint-1.8 (bubbles)                                                         | ✅ delivered                                                                                                          |
| §6.3 Hero Intro          | `hero_intro/1` + `proof_points/0`                                | sprint-1.4                                                                                                         | ✅ delivered (with test-harness extension — see §17 E-2)                                                              |
| §6.4 Message Bubble      | `message_bubble/1` user/assistant                                | sprint-1.6 (stub), sprint-1.8 (full)                                                                               | ✅ delivered (with attribute extensions — see §17 E-1)                                                                |
| §6.5 Composer            | Plane + frame + textarea + send                                  | sprint-1.5                                                                                                         | ✅ delivered (with HTML-validity drift — see §17 D-2)                                                                 |
| §7 LiveView State        | `socket.assigns` shape                                           | sprint-1.3 (initial), sprint-1.6 (events); SPRINT-12 adds `errors`, `stream_task_pid`, `session_id`, rate-limit UX | ✅ delivered (Phase 2 will extend — see §17 F-1)                                                                      |
| §8 Event Handlers        | `send_message`, `scroll_position`, `handle_keydown`, `:stream_*` | sprint-1.6; SPRINT-12 — supervised stream, `assigns.errors`, Hammer rate limit                                     | ✅ delivered (C-1, C-2, C-3 addressed in SPRINT-11/12 — see §17)                                                      |
| §9 OpenAI Streaming      | `Req` + SSE parser                                               | sprint-1.7 (parser), sprint-1.9 (integration)                                                                      | ✅ delivered (with defective patterns — see §17 C-4)                                                                  |
| §10 JS Hooks             | `ChatScroll` + `ChatComposer`                                    | sprint-1.5                                                                                                         | ✅ delivered (covered by Vitest; Sprint 13 will harden first-render binding)                                          |
| §11 Markdown Rendering   | `Earmark` + `prose` classes                                      | sprint-1.8, SPRINT-11                                                                                              | ✅ delivered (C-2 XSS path addressed in SPRINT-11; tooling drift — see §17 D-1)                                       |
| §12 Config               | `OPENAI_API_KEY` in runtime                                      | sprint-1.1                                                                                                         | ✅ delivered (SPRINT-11 TASK 3: key posture scan + rotation docs; optional dev missing-`.env` UX remains a follow-on) |
| §13 Dependencies         | `mix.exs` deps list                                              | sprint-1.1                                                                                                         | ✅ delivered                                                                                                          |
| §14 File Structure       | `lib/`, `assets/`, `config/`                                     | sprint-1.1 → sprint-1.10                                                                                           | ✅ delivered (with module extractions — see §17 E-3)                                                                  |
| §15 Pre-launch Checklist | 16 items                                                         | sprint-1.10                                                                                                        | ✅ all 16 items verified (per-item notes annotated below)                                                             |
| §16 Out of Scope         | Documented exclusions                                            | n/a                                                                                                                | ⏸ unchanged                                                                                                           |

### 0.3 What's missing (acceptance gaps)

None. Every spec-mandated deliverable has corresponding test coverage and was verified by the sprint-1.10 E2E gate. The audit found **no acceptance criteria that were partially met or skipped** within Phase 1 scope. The "partial" items live one layer up in the development pipeline:

- **Defects-in-spec, faithful-in-implementation (§17 C-1 … C-4):** The implementation followed the spec exactly; the spec itself prescribes patterns that the Phase 2 audit later replaced. **C-2 and C-4 are fixed in SPRINT-11**; **C-1 and C-3 are fixed in SPRINT-12 (2026-04-25)** (see §0.4, §0.5, and §17).
- **Tooling drift (§17 D-1, D-2):** Spec text references Tailwind v3 config and an HTML-invalid `<textarea value=...>`; the implementation correctly used Tailwind v4 syntax and a paired `<textarea>` element (see §0.4 / SPRINT-11 TASK 5 for the HTML validity line). The spec narrative still lags the code in places — the code is authoritative.
- **Test-harness leakage (§17 E-2):** A query-param hero override was added to make a sprint-1.4 negative test pass. It is now gated behind an `:allow_hero_override` env flag (Sprint 11 TASK 1 already cleaned the dev/prod path), but the existence of any such bypass is undocumented in the spec.

### 0.4 Phase 2 — SPRINT-11 completion (2026-04-25)

SPRINT-11 closed the highest-priority audit items in the “immediate fixes A” bucket:

- **IF-1 / E-2:** No `Mix.*` at runtime; `?hero_state=` is gated by `Application.get_env(:chat_app, :allow_hero_override, false)` (test env sets it to `true`).
- **IF-2 / §17 C-2:** `ChatApp.Markdown.to_html/1` HTML-escapes input before Earmark (pre-escape + Earmark); assistant bubbles are safe to pass through `raw/1`.
- **IF-3:** Git history scan for `sk-proj-` + rotation note in README/CHANGELOG (no key in history).
- **IF-4 / §17 C-4:** Global `config :chat_app, :openai_model, "gpt-4o"` and `ChatApp.OpenAI` reads it for the request body (per-conversation overrides remain SPRINT-15/16).
- **IF-7 / §17 D-2:** Composer uses a paired `<textarea><%= @input %></textarea>` (valid HTML).

**Phase 2 complete:** All 6 sprints (SPRINT-11 to SPRINT-16) have been completed. See `docs/sprints/README.md`.

### 0.5 Phase 2 — SPRINT-12 completion (2026-04-25)

SPRINT-12 closed the “immediate fixes B: resilience & cleanup” items:

- **IF-5 / C-1 (stream supervision):** `Task.Supervisor` (`ChatApp.TaskSupervisor`) + `stream_task_pid` + `terminate/2` cancellation; no `Task.start/1` in `chat_live` / streaming path.
- **IF-6 / C-3 (prompt poisoning):** `:stream_error` appends to `assigns.errors` and dedicated UI, not to `assigns.messages` sent to OpenAI.
- **IF-5 (rate limit):** Hammer `~> 6.2` with per-session keying and user-visible “slow down” behavior.
- **IF-9 (scaffold):** `PageController` / `PageHTML` scaffold and unused `CoreComponents` / `theme_toggle` removed per task scope; `/page` is unmapped (404).

**Phase 2 progress:** 6 of 6 sprints done (SPRINT-11, 12, 13, 14, 15, 16 complete).

### 0.6 Phase 2 — SPRINT-15 completion (2026-04-27)

SPRINT-15 delivered the largest "demo → product" gap: persistent conversation state and basic auth for non-localhost deploys.

- **F-1 (SQLite + Ecto):** `ChatApp.Repo` + `Ecto.Sqlite3`; `ChatApp.Conversations` context with `get_or_create/1`, `append_message/3`, `update_assistant_message/2`, cascade delete; migration with unique session_id index. Conversation and message rows survive page reload, LiveView crashes, and server restarts (single-node deployment only).
- **H-2 (Basic Auth):** `Plug.BasicAuth` in router pipeline, gated by `BASIC_AUTH_USER` + `BASIC_AUTH_PASSWORD` env vars (prod only; dev/test left open by default). Constant-time password comparison via `Plug.Crypto.secure_compare/2`.
- **TASK 4 (Stop/Regenerate):** User can click "Stop" to kill mid-stream generation; partial assistant text persists in DB and UI. User can click "Regenerate" to re-stream the last user message; the prior assistant message is deleted and a new one is streamed in. Regenerate while streaming is a no-op (prevents racing tasks).
- **TASK 5 (Theme UI):** Sprint 15 introduced persisted theme selection; a later Phase 3 ad-hoc UI pass replaced the original system/light/dark buttons with four named themes (`editorial`, `swiss`, `mid-century`, `techno-brutalist`) backed by `data-theme` + `localStorage`. All theme buttons have non-empty `aria-label`.

**Phase 2 is fully complete:** 6 of 6 sprints done. (Delivered sidebar, settings drawer, usage records, code-block UI, and retries).

---

## 1. Stack

| Concern            | Choice                                       | Notes                                                                  |
| ------------------ | -------------------------------------------- | ---------------------------------------------------------------------- |
| Language           | Elixir `~> 1.16`                             |                                                                        |
| Framework          | Phoenix `~> 1.7` + LiveView `~> 0.20`        |                                                                        |
| Styling            | Tailwind CSS v4                              | `@tailwindcss/vite` plugin                                             |
| Tailwind animation | `tailwindcss-animate`                        | needed for `animate-in`, `fade-in`, `slide-in-from-top-*` hero classes |
| AI                 | OpenAI Chat Completions API — `stream: true` |                                                                        |
| HTTP client        | `Req ~> 0.5`                                 | version matters; `into:` streaming API is 0.5+                         |
| Markdown           | `Earmark ~> 1.4` + `Phoenix.HTML`            | render assistant messages as safe HTML                                 |
| DB                 | none for spec-1                              |                                                                        |
| Auth               | none for spec-1                              |                                                                        |

---

## 2. Fonts

The original loads three Google Fonts families and assigns them to CSS custom properties used throughout the design system. Without these, typography will not match.

Load in the root layout `<head>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link
  href="https://fonts.googleapis.com/css2?family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,560;1,9..144,400&family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
  rel="stylesheet"
/>
```

Then in CSS (before all other imports) bind the families to the custom property vars the design system expects:

```css
:root {
  --font-ibm-plex-sans: "IBM Plex Sans", sans-serif;
  --font-ibm-plex-mono: "IBM Plex Mono", monospace;
  --font-fraunces: "Fraunces", serif;
}
```

`foundation.css` then maps these into:

```css
--font-body: var(--font-ibm-plex-sans, sans-serif);
--font-display: var(--font-fraunces, serif);
--font-mono: var(--font-ibm-plex-mono, monospace);
--font-base: var(--font-body);
--font-label: var(--font-body);
```

---

## 3. CSS Architecture

### 3.1 Files to copy verbatim

Copy these four files from the reference project into `assets/css/`:

| Source                          | Destination                 |
| ------------------------------- | --------------------------- |
| `src/app/styles/foundation.css` | `assets/css/foundation.css` |
| `src/app/styles/shell.css`      | `assets/css/shell.css`      |
| `src/app/styles/utilities.css`  | `assets/css/utilities.css`  |
| `src/app/styles/chat.css`       | `assets/css/chat.css`       |

### 3.2 Import order in `assets/css/app.css`

Order is load-order-sensitive. `chat.css` and `utilities.css` share class names; `utilities.css` must come first because `chat.css` uses `.focus-ring` and `.theme-body` defined there.

```css
@import "tailwindcss";
@import "./foundation.css";
@import "./shell.css";
@import "./utilities.css";
@import "./chat.css";

/* Bind font family vars BEFORE foundation.css token resolution */
:root {
  --font-ibm-plex-sans: "IBM Plex Sans", sans-serif;
  --font-ibm-plex-mono: "IBM Plex Mono", monospace;
  --font-fraunces: "Fraunces", serif;
}

/* Dark mode: use .dark class, not prefers-color-scheme */
@custom-variant dark (&:where(.dark, .dark *));
```

### 3.3 Key design tokens (reference)

These are the tokens most used in the chat surface. All are defined in `foundation.css` `:root`.

```css
/* --- Colour layer --- */
--background: oklch(0.98 0.01 250) /* page background */
  --foreground: oklch(0.21 0.01 250) /* primary text */ --surface: oklch(1 0 0)
  /* card / panel surfaces */ --surface-hover: oklch(0.96 0.01 250)
  --surface-muted: oklch(0.96 0.02 265) --accent: oklch(0.42 0.12 280)
  /* brand purple */ --accent-interactive: var(--accent)
  --accent-foreground: oklch(1 0 0) --border: oklch(0.9 0.01 250)
  --shadow-base: oklch(0.15 0.01 250) /* used in box-shadow color-mix() calls */
  --highlight-base: white /* used in inner-glow box-shadows */
  --glass-sublayer: oklch(0.95 0 0) /* base for backdrop-blur surfaces */
  /* Dark overrides (on .dark) */ --background: oklch(0.12 0.014 300)
  --foreground: oklch(0.98 0.01 250) --surface: oklch(0.19 0.012 290)
  --accent: oklch(0.78 0.1 290) --shadow-base: oklch(0 0 0)
  --highlight-base: var(--foreground) --glass-sublayer: oklch(0.2 0 0)
  /* --- Spacing ladder --- */ --space-1: 0.25rem --space-2: 0.5rem
  --space-3: 0.75rem --space-4: 1rem --space-6: 1.5rem --space-8: 2rem
  --space-10: 2.5rem --space-12: 3rem --space-16: 4rem
  /* --- Golden-ratio micro-scale (phi) --- */ --phi-2: 0.382rem
  --phi-1: 0.618rem --phi-1p: 1.618rem /* --- Chat surface consumers --- */
  --chat-composer-radius: var(--fva-shell-radius-composer) /* = 2rem */
  --chat-composer-min-height: calc(2.75rem + var(--input-padding) * 2)
  --chat-scroll-cta-offset: calc(var(--space-frame-wide) + var(--space-4))
  --fva-shell-radius-composer: 2rem --fva-shell-radius-control: 999px
  --fva-shell-radius-panel: 1.45rem --input-padding: var(--space-inset-compact)
  /* = 0.75rem */ /* --- Hero typographic scale --- */
  --hero-title-font-size: var(--tier-display-size)
  /* clamp(3.2rem, 5.4vw, 4.65rem) */ --hero-title-line-height: 0.94
  --hero-body-font-size: var(--tier-body-size) /* 1.02rem */
  --hero-body-line-height: 1.42 --tier-display-tracking: -0.055em
  --hero-title-max-width: 10.2ch --hero-greeting-max-width: 37rem
  --hero-intro-stack-gap: 1.15rem --hero-badge-gap: var(--phi-2) /* 0.382rem */
  --hero-badge-padding-inline: 0.8rem --hero-badge-padding-block: 0.28rem;
```

### 3.4 Dark mode

The CSS system uses a `.dark` class on `<html>` (not `prefers-color-scheme`). For spec-1, default to light mode by ensuring `<html>` has no `.dark` class. The design system transitions smoothly between modes when it is toggled.

`foundation.css` also defines `html` and `body` base styles that are required:

```css
html,
body {
  block-size: 100%;
  inline-size: 100%;
  min-block-size: 100%;
  margin: 0;
  padding: 0;
  overflow-x: hidden;
}
body {
  font-family: var(--font-base, sans-serif);
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
```

These are already in the copied `foundation.css` — do not duplicate them.

---

## 4. Root Layout & Height Propagation

The 3-row CSS grid that fills the viewport only works if every ancestor element propagates full height. Phoenix's default `root.html.heex` must have `h-full` (or `height: 100%`) on both `<html>` and `<body>`, and the inner `<main>` wrapper must also fill height.

`lib/chat_app_web/components/layouts/root.html.heex` (key parts):

```heex
<!DOCTYPE html>
<html lang="en" class="" style="height:100%">
  <head>
    <!-- font preconnects and link tag here -->
    <link rel="stylesheet" href={~p"/assets/app.css"} />
  </head>
  <body class="bg-background text-foreground" style="height:100%; overflow:hidden;">
    <%= @inner_content %>
  </body>
</html>
```

`lib/chat_app_web/components/layouts/app.html.heex`:

```heex
<main class="h-full w-full overflow-hidden" style="height:100%;">
  <%= @inner_content %>
</main>
```

The `overflow: hidden` on `body` is intentional — the chat viewport scroll is self-contained inside the section; we do not want the page to scroll.

---

## 5. Page Layout

Route: `live "/", ChatLive, :index`

`ChatLive` renders a single full-viewport `<section>` with a 3-row grid:

```
┌──────────────────────────────────────────┐  ← auto height
│  Header  (glassmorphism border-b)         │
├──────────────────────────────────────────┤  ← minmax(0, 1fr)
│  Message Viewport  (overflow-y-auto)      │
├──────────────────────────────────────────┤  ← auto height
│  Composer Plane  (gradient + blur)        │
│    └── Composer Frame  (input + send)     │
└──────────────────────────────────────────┘
```

Root `<section>` classes (exact match to original):

```
relative grid h-full min-h-0 flex-1 grid-rows-[auto_minmax(0,1fr)_auto] bg-background
```

---

## 6. Component Markup

### 6.1 Header

For spec-1 the header bar is purely decorative — no controls. The glassmorphism effect comes from the `ui-chat-header-surface` class in `chat.css`.

```heex
<div class="ui-chat-header-surface relative z-20 flex shrink-0 items-center
            justify-end border-b border-[--border-color] px-[--space-3] py-[--space-2]"
     data-chat-surface-header="true"
     data-chat-surface-header-mode="embedded">
  <%!-- spec-1: no controls; placeholder for future menu --%>
</div>
```

`ui-chat-header-surface` (from `chat.css`) provides:

- `background: color-mix(in oklab, var(--glass-sublayer) 78%, transparent)`
- `backdrop-filter: blur(24px) saturate(140%)`
- Layered box-shadow: outer depth + inner highlight inset

### 6.2 Message Viewport

```heex
<div class="relative flex h-full min-h-0 w-full flex-col overflow-hidden"
     data-chat-message-region="true">

  <%!-- Radial glow at top of transcript --%>
  <div class={[
    "ui-chat-viewport-glow pointer-events-none absolute inset-x-0 top-0",
    if(@hero_state, do: "h-24 opacity-45", else: "h-32 opacity-70")
  ]} aria-hidden="true" />

  <%!-- Scrollable transcript --%>
  <div id="chat-viewport"
       phx-hook="ChatScroll"
       class="ui-chat-transcript-plane ui-chat-transcript-frame z-10 flex h-full
              min-h-0 flex-1 flex-col overflow-y-auto overscroll-contain"
       data-chat-message-viewport="true"
       data-chat-transcript-mode="embedded">

    <div class={[
      "shrink-0 w-full flex min-h-full flex-col",
      if(@hero_state, do: "justify-center", else: "justify-end")
    ]} data-chat-message-stack="true">

      <%= if @hero_state do %>
        <%!-- Hero intro section --%>
        <.hero_intro />
      <% else %>
        <%!-- Message list --%>
        <%= for msg <- @messages do %>
          <.message_bubble message={msg} />
        <% end %>

        <%= if @is_sending && @stream_buffer == "" do %>
          <%!-- Typing indicator --%>
          <div class="ui-chat-message-assistant max-w-[80%] rounded-2xl
                      px-[--chat-bubble-padding-inline] py-[--chat-bubble-padding-block]
                      text-sm opacity-60 animate-pulse">
            …
          </div>
        <% end %>
      <% end %>
    </div>
  </div>

  <%!-- Scroll-to-bottom pill (visibility toggled by ChatScroll hook) --%>
  <div id="scroll-cta-dock"
       class="ui-chat-scroll-cta-dock absolute left-0 right-0 z-10 flex
              justify-center pointer-events-none hidden"
       style={"bottom: calc(var(--chat-scroll-cta-offset) + var(--safe-area-inset-bottom))"}>
    <button id="scroll-to-bottom"
            class="ui-chat-scroll-cta pointer-events-auto focus-ring min-h-11
                   rounded-full px-[--space-4] py-[--space-2] text-[11px]
                   font-bold transition-all hover:scale-[1.03]"
            aria-label="Scroll to bottom">
      ↓ Scroll to bottom
    </button>
  </div>
</div>
```

### 6.3 Hero Intro (function component)

Rendered when `@hero_state == true` (no messages yet). Disappears permanently on first send.

```heex
defp hero_intro(assigns) do
  ~H"""
  <div data-homepage-chat-intro="true"
       class="mx-auto flex w-full max-w-4xl flex-col items-center justify-center
              px-[--space-3] text-center animate-in fade-in slide-in-from-top-4
              duration-700 ease-out fill-mode-both
              pb-[--hero-intro-stack-gap] space-y-[--hero-intro-stack-gap]">

    <%!-- Service chips cluster --%>
    <div class="ui-chat-brand-chip-cluster flex flex-wrap items-center justify-center
                gap-x-[--hero-badge-gap] gap-y-[--phi-2] rounded-full
                px-[--hero-badge-padding-inline] py-[--hero-badge-padding-block]
                text-[0.66rem] font-medium uppercase tracking-[0.18em] text-foreground/56">
      <span data-homepage-service-chip="true">Chat</span>
      <span aria-hidden="true" class="hidden text-foreground/20 sm:inline">/</span>
      <span data-homepage-service-chip="true">Search</span>
      <span aria-hidden="true" class="hidden text-foreground/20 sm:inline">/</span>
      <span data-homepage-service-chip="true">Publish</span>
    </div>

    <%!-- Hero heading — display font (Fraunces) via theme-display utility --%>
    <h2 class="theme-display text-foreground font-semibold text-balance"
        style="max-width: var(--hero-title-max-width);
               font-size: var(--hero-title-font-size);
               line-height: var(--hero-title-line-height);
               letter-spacing: var(--tier-display-tracking);">
      One compact system for AI-assisted work
    </h2>

    <%!-- Hero subheading — body font --%>
    <p class="theme-body text-foreground/64"
       style="max-width: var(--hero-greeting-max-width);
              font-size: var(--hero-body-font-size);
              line-height: var(--hero-body-line-height);">
      Chat with your AI assistant. Ask anything.
    </p>

    <%!-- Proof-point cards strip --%>
    <div class="grid w-full max-w-5xl gap-3 pt-[--phi-2] text-left sm:grid-cols-3"
         data-homepage-proof-strip="true">
      <%= for %{title: title, body: body} <- proof_points() do %>
        <div class="rounded-3xl border border-foreground/10 bg-background/75
                    px-4 py-4 shadow-[0_18px_50px_-32px_rgba(15,23,42,0.28)]
                    backdrop-blur-sm" data-homepage-proof-card="true">
          <p class="text-xs font-semibold uppercase tracking-[0.16em] text-foreground/46">
            <%= title %>
          </p>
          <p class="mt-2 text-sm leading-6 text-foreground/74">
            <%= body %>
          </p>
        </div>
      <% end %>
    </div>
  </div>
  """
end

defp proof_points do
  [
    %{title: "One compact system",
      body: "Chat, search, jobs, and publishing stay inside one app footprint."},
    %{title: "Background AI workflows",
      body: "Deferred jobs keep long-running work visible, retryable, and under control."},
    %{title: "Governed by default",
      body: "Role-aware tools, prompts, and workflow actions stay aligned with the operator model."}
  ]
end
```

### 6.4 Message Bubble (function component)

```heex
defp message_bubble(%{message: %{role: :user}} = assigns) do
  ~H"""
  <div class="ui-chat-message-user ml-auto max-w-[80%] rounded-2xl
              px-[--chat-bubble-padding-inline] py-[--chat-bubble-padding-block]
              text-sm">
    <%= @message.content %>
  </div>
  """
end

defp message_bubble(%{message: %{role: :assistant}} = assigns) do
  ~H"""
  <div class="ui-chat-message-assistant max-w-[80%] rounded-2xl
              px-[--chat-bubble-padding-inline] py-[--chat-bubble-padding-block]
              text-sm prose prose-sm max-w-none">
    <%= raw(render_markdown(@message.content)) %>
  </div>
  """
end
```

`render_markdown/1` (in the LiveView module or a helper):

```elixir
defp render_markdown(text) do
  {:ok, html, _} = Earmark.as_html(text,
    escape: false,      # trust our own content (not user input)
    smartypants: false
  )
  html
end
```

### 6.5 Composer Plane + Frame

The composer sits inside two wrappers — `ui-chat-composer-plane` (gradient + blur background) and `ui-chat-composer-frame` (the rounded input container). Both are required for the visual match.

```heex
<div class="flex flex-col gap-[--space-2]" data-chat-bottom-rail="true">

  <%!-- Composer plane: gradient fade-in background above input --%>
  <div class="ui-chat-composer-plane relative flex-none
              px-[--space-3] pt-[--space-1] pb-[--space-2]"
       data-chat-composer-row="true">

    <%!-- Hairline seam (visible separator at top of plane) --%>
    <div aria-hidden="true"
         class="ui-chat-composer-seam pointer-events-none absolute
                inset-x-[--space-16] top-0 h-px" />

    <%!-- Centered max-width shell --%>
    <div class="mx-auto w-full max-w-3xl" data-chat-composer-shell="true">

      <form phx-submit="send_message"
            class={[
              "ui-chat-composer-frame ui-chat-composer-frame-hover",
              "relative flex min-h-[--chat-composer-min-height] items-stretch",
              "gap-[--space-2] overflow-hidden rounded-[--chat-composer-radius]",
              "transition-all duration-300",
              "focus-within:ui-chat-composer-frame-focus"
            ]}
            data-chat-composer-form="true"
            data-chat-composer-state={if String.trim(@input) != "", do: "ready", else: "idle"}>

        <textarea id="chat-input"
                  name="input"
                  phx-hook="ChatComposer"
                  phx-keydown="handle_keydown"
                  rows="1"
                  placeholder="Ask..."
                  value={@input}
                  class="flex-1 resize-none bg-transparent
                         px-[--chat-composer-field-padding-inline]
                         py-[--chat-composer-field-padding-block]
                         text-sm outline-none"
                  style="max-height: 192px; overflow-y: hidden;"
                  disabled={@is_sending} />

        <button type="submit"
                disabled={@is_sending || String.trim(@input) == ""}
                class="ui-chat-send-button shrink-0 self-center
                       rounded-[--fva-shell-radius-control]
                       p-[--space-2] mr-[--space-2]
                       transition-all active:scale-95
                       disabled:opacity-40 disabled:cursor-not-allowed"
                aria-label="Send message">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
               stroke="currentColor" stroke-width="2.5"
               stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"/>
            <polygon points="22 2 15 22 11 13 2 9 22 2"/>
          </svg>
        </button>
      </form>
    </div>
  </div>
</div>
```

`ui-chat-composer-plane` (from `chat.css`) provides:

- `background: linear-gradient(180deg, color-mix(in oklab, var(--background) 56%, transparent) 0%, ..., var(--background) 100%)`
- `backdrop-filter: blur(8px)`
- Subtle top box-shadow

`ui-chat-composer-frame` (from `chat.css`) provides:

- `background: linear-gradient(180deg, color-mix(in oklab, var(--glass-sublayer) 80%, ...) ...)`
- `backdrop-filter: blur(14px)`
- Border: `color-mix(in oklab, var(--foreground) 8%, transparent)`
- `padding: var(--input-padding)` (0.75rem)

`ui-chat-composer-seam` (from `chat.css`) provides:

- `background: var(--fva-shell-composer-plane-seam)` — a hairline `color-mix(in oklab, var(--foreground) 8%, transparent)`

---

## 7. LiveView State

```elixir
# socket.assigns shape
%{
  messages:      [],        # [%{role: :user | :assistant, content: String.t()}]
  input:         "",        # current textarea value
  is_sending:    false,     # true while stream is running
  stream_buffer: "",        # accumulates partial tokens for the in-progress assistant msg
  at_bottom:     true,      # scroll position tracking (updated by JS hook)
  hero_state:    true       # true until first message is sent; never goes back to true
}
```

---

## 8. LiveView Event Handlers

```elixir
def handle_event("send_message", %{"input" => text}, socket) do
  text = String.trim(text)
  if text == "" || socket.assigns.is_sending do
    {:noreply, socket}
  else
    user_msg = %{role: :user, content: text}
    messages  = socket.assigns.messages ++ [user_msg]

    # Fire-and-forget streaming task — must NOT use Task.async (requires await)
    pid = self()
    Task.start(fn -> stream_openai(messages, pid) end)

    {:noreply,
     assign(socket,
       messages:      messages,
       input:         "",
       is_sending:    true,
       stream_buffer: "",
       hero_state:    false   # ← hero disappears permanently on first send
     )}
  end
end

def handle_event("handle_keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
  # Enter without shift: submit (delegated via JS hook, but also handled here for purity)
  {:noreply, socket}
end

def handle_event("scroll_position", %{"at_bottom" => at_bottom}, socket) do
  {:noreply, assign(socket, at_bottom: at_bottom)}
end

# Incoming stream token from Task
def handle_info({:stream_token, token}, socket) do
  buffer   = socket.assigns.stream_buffer <> token
  messages = upsert_assistant_message(socket.assigns.messages, buffer)
  {:noreply, assign(socket, messages: messages, stream_buffer: buffer)}
end

# Stream complete
def handle_info(:stream_done, socket) do
  {:noreply, assign(socket, is_sending: false, stream_buffer: "")}
end

# Stream error
def handle_info({:stream_error, reason}, socket) do
  error_msg = %{role: :assistant, content: "Error: #{inspect(reason)}"}
  messages  = socket.assigns.messages ++ [error_msg]
  {:noreply, assign(socket, messages: messages, is_sending: false, stream_buffer: "")}
end

# Append or update the last assistant message in-place
defp upsert_assistant_message(messages, buffer) do
  case List.last(messages) do
    %{role: :assistant} ->
      List.update_at(messages, -1, fn _ -> %{role: :assistant, content: buffer} end)
    _ ->
      messages ++ [%{role: :assistant, content: buffer}]
  end
end
```

---

## 9. OpenAI Streaming

### 9.1 Request

```elixir
defmodule ChatApp.OpenAI do
  @api_url "https://api.openai.com/v1/chat/completions"

  def stream(messages, lv_pid) do
    body = %{
      model:    "gpt-4o",
      stream:   true,
      messages: Enum.map(messages, fn %{role: role, content: content} ->
        %{role: Atom.to_string(role), content: content}
      end)
    }

    Req.post(@api_url,
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      json: body,
      receive_timeout: 120_000,
      into: fn {:data, chunk}, acc ->
        parse_sse_chunk(chunk, acc, lv_pid)
      end
    )

    send(lv_pid, :stream_done)
  rescue
    error -> send(lv_pid, {:stream_error, error})
  end

  defp api_key, do: Application.fetch_env!(:chat_app, :openai_api_key)
end
```

### 9.2 SSE chunk parser

**Critical:** Req delivers raw TCP chunks. A single chunk may contain multiple `data:` lines, or a line may be split across two chunks. A line-splitting accumulator is required.

```elixir
# Parse one raw binary chunk; acc is the leftover partial line from the prior chunk.
defp parse_sse_chunk(raw, acc, lv_pid) do
  combined = (acc || "") <> raw

  {lines, leftover} =
    combined
    |> String.split("\n")
    |> split_lines_and_remainder()

  Enum.each(lines, fn line ->
    case line do
      "data: [DONE]" ->
        :ok  # stream_done sent after Req.post returns

      "data: " <> json ->
        with {:ok, body}    <- Jason.decode(json),
             content when is_binary(content) <-
               get_in(body, ["choices", Access.at(0), "delta", "content"]) do
          send(lv_pid, {:stream_token, content})
        else
          _ -> :ok
        end

      _ ->
        :ok
    end
  end)

  {:cont, leftover}
end

# Returns {complete_lines, partial_last_line}
defp split_lines_and_remainder(parts) do
  {init, [last]} = Enum.split(parts, length(parts) - 1)
  complete = Enum.reject(init, &(&1 == ""))
  {complete, last}
end
```

Call from the LiveView send handler:

```elixir
defp stream_openai(messages, pid) do
  ChatApp.OpenAI.stream(messages, pid)
end
```

---

## 10. JS Hooks

Two hooks in `assets/js/hooks/`. Register both in `app.js`.

### `ChatScroll`

Tracks whether the viewport is pinned to the bottom. Auto-scrolls on LiveView DOM updates if user is at the bottom. Shows/hides the scroll-to-bottom pill.

```js
const ChatScroll = {
  mounted() {
    this.isAtBottom = true;
    this.el.addEventListener("scroll", () => this.onScroll(), {
      passive: true,
    });
    this.scrollToBottom();
  },

  updated() {
    // LiveView patched new content — scroll if pinned
    if (this.isAtBottom) this.scrollToBottom();
  },

  onScroll() {
    const { scrollTop, scrollHeight, clientHeight } = this.el;
    this.isAtBottom = scrollHeight - scrollTop - clientHeight < 40;
    this.pushEvent("scroll_position", { at_bottom: this.isAtBottom });

    const dock = document.getElementById("scroll-cta-dock");
    if (dock) dock.classList.toggle("hidden", this.isAtBottom);

    const btn = document.getElementById("scroll-to-bottom");
    if (btn) btn.onclick = () => this.scrollToBottom();
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

export default ChatScroll;
```

### `ChatComposer`

Auto-resizes textarea. Intercepts `Enter` (without Shift) to submit the form rather than insert a newline.

```js
const ChatComposer = {
  mounted() {
    this.resize();
    this.el.addEventListener("input", () => this.resize());
    this.el.addEventListener("keydown", (e) => this.onKeyDown(e));
  },

  updated() {
    // LiveView reset the value (e.g. after send) — resize back to 1 row
    this.resize();
  },

  resize() {
    const el = this.el;
    el.style.height = "0px";
    const next = Math.min(el.scrollHeight, 192);
    el.style.height = next + "px";
    el.style.overflowY = el.scrollHeight > 192 ? "auto" : "hidden";
  },

  onKeyDown(e) {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault();
      this.el.closest("form")?.requestSubmit();
    }
  },
};

export default ChatComposer;
```

`assets/js/app.js` registration:

```js
import ChatScroll from "./hooks/ChatScroll";
import ChatComposer from "./hooks/ChatComposer";

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ChatScroll, ChatComposer },
});
```

---

## 11. Markdown Rendering

Assistant content from OpenAI is Markdown. Rendering it raw as text would display `**bold**` as literal asterisks and break code blocks.

Use `Earmark` in `mix.exs`:

```elixir
{:earmark, "~> 1.4"}
```

Helper (in a `ChatAppWeb.ChatHelpers` module or directly in the LiveView):

```elixir
defp render_markdown(text) do
  {:ok, html, _} = Earmark.as_html(text,
    escape: false,      # trust our own content (not user input)
    smartypants: false
  )
  html
end
```

In the template use `raw/1` from `Phoenix.HTML` to output the compiled HTML:

```heex
<%= raw(render_markdown(@message.content)) %>
```

**Security note:** This renders OpenAI output (trusted). Do NOT use `raw()` on unfiltered user input.

Add Tailwind's `@tailwindcss/typography` plugin for prose styling of Markdown output:

```js
// tailwind.config.js
plugins: [require("@tailwindcss/typography")];
```

Apply `prose prose-sm max-w-none` on the assistant bubble wrapper.

---

## 12. Config

```elixir
# config/runtime.exs
config :chat_app, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")
```

`.env` (gitignored — add to `.gitignore`):

```
OPENAI_API_KEY=sk-...
```

Load with `export $(cat .env | xargs)` or use a tool like `dotenvy` (`{:dotenvy, "~> 0.8"}` in dev deps).

---

## 13. `mix.exs` Dependencies

```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
    {:plug_cowboy, "~> 2.7"},
    {:req, "~> 0.5"},           # streaming API requires 0.5+
    {:earmark, "~> 1.4"},       # markdown → HTML
    {:jason, "~> 1.4"},         # JSON (SSE payload parsing)
    {:dotenvy, "~> 0.8", only: :dev}
  ]
end
```

---

## 14. File Structure

```
lib/
  chat_app_web/
    live/
      chat_live.ex               # LiveView: mounts assigns, handles events, handles_info
    components/
      layouts/
        root.html.heex           # html/body with h-full, font links
        app.html.heex            # <main class="h-full ...">
    router.ex                    # live "/", ChatLive, :index
  chat_app/
    openai.ex                    # Req wrapper + SSE line parser

assets/
  css/
    app.css                      # import order: foundation → shell → utilities → chat
    foundation.css               # copied from reference — tokens + base styles
    shell.css                    # copied from reference — nav/shell utilities
    utilities.css                # copied from reference — focus-ring, theme-*, tier-*
    chat.css                     # copied from reference — ui-chat-* classes
  js/
    app.js                       # LiveSocket setup + hook registration
    hooks/
      ChatScroll.js
      ChatComposer.js

config/
  config.exs
  runtime.exs                    # OPENAI_API_KEY

.env                             # gitignored
.gitignore                       # must include .env and /deps /priv/static/assets
```

---

## 15. Checklist Before Calling Spec-1 Done

> **Status as of 2026-04-24:** all 16 items verified by sprint-1.10. Inline notes flag drift between the prescription and the implementation.

- [x] `html` and `body` both have `height: 100%` — viewport grid requires it · _delivered sprint-1.3_
- [x] Font `<link>` tag present in root layout `<head>` · _delivered sprint-1.2_
- [x] CSS import order: `foundation` → `shell` → `utilities` → `chat` · _delivered sprint-1.2_
- [x] `tailwindcss-animate` in `devDependencies` — needed for hero animation classes · _delivered sprint-1.1; loaded via Tailwind v4 `@plugin` syntax in `app.css`, not `tailwind.config.js` (drift §17 D-1)_
- [x] `@tailwindcss/typography` in `devDependencies` — needed for `prose` on assistant bubbles · _delivered sprint-1.1; loaded via `@plugin` syntax (drift §17 D-1)_
- [x] `Req ~> 0.5` in deps — earlier versions do not support `into:` streaming · _delivered sprint-1.1_
- [x] `Jason` in deps — SSE JSON parsing · _delivered sprint-1.1_
- [x] `Earmark` in deps — Markdown rendering · _delivered sprint-1.1_
- [x] `OPENAI_API_KEY` in `runtime.exs` with `fetch_env!` · _delivered sprint-1.1; runtime.exs branches on both `:dev` and `:prod` (spec showed only `:prod`); SPRINT-11 TASK 3 documented key rotation + git scan; friendlier missing-`.env` dev UX remains optional follow-on_
- [x] `.env` added to `.gitignore` · _delivered sprint-1.1_
- [x] Fire-and-forget stream (not `Task.async` from the LiveView) · _sprint-1.6 used `Task.start` (defective — §17 C-1); **SPRINT-12 TASK 1** replaced with `Task.Supervisor.start_child/2` under `ChatApp.TaskSupervisor` + `stream_task_pid` + `terminate/2` cancellation (drift addressed; spec text in §8/§15 left historical)_
- [x] SSE parser handles chunk boundary splits (line-splitting accumulator) · _delivered sprint-1.7, integration-tested sprint-1.9_
- [x] `ui-chat-composer-plane` wrapper present — omitting it loses the gradient background · _delivered sprint-1.5_
- [x] `ui-chat-composer-seam` hairline div present · _delivered sprint-1.5_
- [x] `hero_state: false` set on first send (never reverts to `true`) · _delivered sprint-1.6_
- [x] `phx-hook="ChatScroll"` on the scroll container, `phx-hook="ChatComposer"` on textarea · _delivered sprint-1.5_

---

## 16. Out of Scope for Spec-1

- Auth / sessions / user accounts
- Conversation persistence (Ecto / DB)
- File attachments (drag-and-drop, file picker)
- `@mention` system
- Tool/capability plugin cards (charts, audio, web-search results, etc.)
- Admin panel
- Floating chat mode (non-home pages)
- Job queue (Oban / background workers)
- MCP process sidecars
- Dark mode toggle
- Density toggle (compact / default / relaxed)

---

## 17. Drift Log (audit added 2026-04-24)

This section is a frozen record of every meaningful difference between what this spec prescribes and what sprints 1.1–1.10 actually shipped. Entries are grouped by **why** the drift exists. Codes (`C-N`, `D-N`, `E-N`, `F-N`) are referenced from §0 and from Phase 2 sprint backlog items.

### C — Spec prescribes a defective pattern (implementation followed spec; Phase 2 will replace)

Each of these items was implemented exactly as the spec demanded. Subsequent code review (the same audit that produced §0) classified the prescribed pattern as a defect. **C-2 and C-4 were addressed in SPRINT-11 (2026-04-25);** **C-1 and C-3 were addressed in SPRINT-12 (2026-04-25).** The spec text below is preserved so the original prescription stays visible.

| Code | Spec section               | What spec said                                                                                         | Why it's defective                                                                                                                                                                                                                                                                                                                            | Fixed by                                                                                                                                                                             |
| ---- | -------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| C-1  | §8 + §15 item 11           | `pid = self(); Task.start(fn -> stream_openai(messages, pid) end)`                                     | Unsupervised — task crashes orphan no supervisor restart, no telemetry, and a `raise` inside the task escapes the `try/rescue` because `Task.start` already detached. The `error` in the rescue clause is shadowed (variable `error` was never `Exception.message/1`-formatted).                                                              | **✅ SPRINT-12** — `Task.Supervisor.start_child(ChatApp.TaskSupervisor, ...)` + `stream_task_pid` + `terminate/2` with `Process.alive?/1` guard (not `async_nolink`; see sprint doc) |
| C-2  | §11 + §6.4 markdown helper | `Earmark.as_html(text, escape: false, smartypants: false)`                                             | `escape: false` allows raw HTML from any source to pass through to the browser. Spec assumes "OpenAI output is trusted", but (a) OpenAI can quote user input verbatim, (b) the same helper will be reused for system prompts, error strings, and (post-Phase-2) titles — none of which are guaranteed safe.                                   | **✅ SPRINT-11** — `Phoenix.HTML` pre-escapes the Markdown string before Earmark; `HtmlSanitizeEx` not added in this task (see §0.4)                                                 |
| C-3  | §8 `:stream_error` handler | `error_msg = %{role: :assistant, content: "Error: #{inspect(reason)}"}; messages = ... ++ [error_msg]` | Error strings are spliced into `messages`, which is the same list that gets serialized back to OpenAI on the next turn. Models then see `"Error: %Req.TransportError{reason: :nxdomain}"` as part of the conversation and start apologizing for it. Errors should live in a separate `assigns.errors` channel and render as ephemeral toasts. | **✅ SPRINT-12** — `assigns.errors` + `[data-chat-message-error]` UI; not mixed into outbound API `messages`                                                                         |
| C-4  | §9.1 request body          | `model: "gpt-4o"` hardcoded in the request body                                                        | Model selection is a per-conversation runtime decision (cost, capability, reasoning vs. chat, eval matrix). Hardcoding it forces a recompile to A/B test.                                                                                                                                                                                     | **✅ SPRINT-11** — `config :chat_app, :openai_model, "gpt-4o"` + `Application.get_env/3` in `ChatApp.OpenAI` (per-conversation model still SPRINT-15/16, F-3)                        |

### D — Tooling drift (spec text is outdated; implementation is correct)

These are cases where the spec text describes a v3-era tooling pattern, the sprint implemented the v4-era pattern instead, and the spec was never updated. The code is correct; the **spec text** should be revised whenever this section is rewritten as `spec-2`.

| Code | Spec section         | Spec says                                                                                       | Implementation does                                                                                               | Why implementation wins                                                                                                                                               |
| ---- | -------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| D-1  | §3.2, §11            | Wire Tailwind plugins via `tailwind.config.js`: `plugins: [require("@tailwindcss/typography")]` | `app.css` declares `@plugin "@tailwindcss/typography"` and `@plugin "tailwindcss-animate"` (delivered sprint-1.2) | Tailwind v4 deprecates JS-based config in favor of `@plugin` directives in CSS. Spec §3.2 already shows the v4 import order; §11 contradicts it.                      |
| D-2  | §6.5 composer markup | `<textarea ... value={@input} disabled={@is_sending} />` (self-closing, value as attribute)     | `<textarea ...><%= @input %></textarea>` (paired tag, value as text content) — **confirmed in SPRINT-11 TASK 5**  | `<textarea>` is a void-element exception per the HTML spec — `value=` is ignored by browsers. The paired form is the only one that actually displays the bound value. |

### E — Implementation extensions (additions beyond spec, kept intentionally)

These are surfaces the spec did not mention but the sprints added because they were needed for testability or robustness. They are **not defects** but they are not in the spec either, so a future reader would be confused.

| Code | Where                 | What was added                                                                                                                                     | Reason                                                                                                                       | Sprint                                                                                               |
| ---- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| E-1  | §6.4 message bubbles  | `data-chat-message-bubble` and `data-role="user"`/`"assistant"` attributes                                                                         | Required by `chat_live_bubbles_test.exs` Floki selectors and by the Wallaby E2E `[data-role='assistant']` queries            | sprint-1.6, sprint-1.8                                                                               |
| E-2  | §6.3 hero state       | `parse_hero_state(params)` reads `?hero_state=false` from the URL on mount, gated by `Application.get_env(:chat_app, :allow_hero_override, false)` | Sprint 1.4 needed a deterministic way to render the post-hero view in tests without going through the full send-message flow | sprint-1.4; gating added by SPRINT-11 TASK 1 (originally `Mix.env() == :test`, which broke releases) |
| E-3  | §8, §11 module layout | `upsert_assistant_message/2` extracted to `ChatApp.Chat`; `render_markdown/1` extracted to `ChatApp.Markdown.to_html/1`                            | Spec described both as `defp` inside `ChatLive`. Pure functions are unit-tested directly without booting LiveView.           | sprint-1.6, sprint-1.8                                                                               |
| E-4  | §8 keydown            | Catch-all `handle_event("handle_keydown", _params, socket)` clause added below the Enter clause                                                    | Without it, every non-Enter keystroke crashes the LiveView with `FunctionClauseError` — `phx-keydown` fires on every key     | sprint-1.6                                                                                           |
| E-5  | §9 + §12 config       | `api_url/0` reads `Application.get_env(:chat_app, :openai_api_url, @default_api_url)`                                                              | Bypass integration tests need to redirect the OpenAI call to a local port                                                    | sprint-1.7                                                                                           |
| E-6  | §8 dispatch           | `openai_module/0` shim reads `Application.get_env(:chat_app, :openai_module, ChatApp.OpenAI)`                                                      | Test env injects `ChatApp.OpenAI.Stub` so LiveView event tests run offline                                                   | sprint-1.6                                                                                           |

### F — Latent drift (will appear after Phase 2 lands)

Items that are NOT yet drift but **will become drift** as soon as the listed Phase 2 sprint merges. Listed here so the spec-2 author has a complete picture.

| Code | Spec section      | What changes                                                                                                                                                     | Triggered by                                                                                             |
| ---- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| F-1  | §7 socket assigns | Adds `:errors`, `:stream_task_pid`, session / rate-limit-related assigns (Phase 2A) and `:conversation_id`, `:settings_drawer_open?`, `:active_panel` (Phase 2B) | **Partial — SPRINT-12** (`errors`, `stream_task_pid`, `session_id`, rate-limit UX); SPRINT-15, SPRINT-16 |
| F-2  | §8 event handlers | Adds `"stop_stream"`, `"regenerate"`, `"select_conversation"`, `"new_conversation"`, `"open_settings"`, `"copy_message"`, `"feedback"`                           | SPRINT-15, SPRINT-16                                                                                     |
| F-3  | §9.1 request body | Per-conversation `model`, `temperature`, `system_prompt` (overrides `:openai_model` env default)                                                                 | SPRINT-15, SPRINT-16                                                                                     |
| F-4  | §12 config        | Adds `BASIC_AUTH_USER`/`BASIC_AUTH_PASS`, `DATABASE_URL` (SQLite), Hammer rate-limit ETS backend config                                                          | **Partial — SPRINT-12** (`config :hammer` for ETS backend); SPRINT-15                                    |
| F-5  | §13 deps          | Adds `:ecto_sql`, `:ecto_sqlite3`, `:hammer`, `:phoenix_ecto`, `:plug_basic_auth` (test/prod), `:html_sanitize_ex` (optional; not added in SPRINT-11)            | **Partial — SPRINT-12** (`:hammer`); SPRINT-15                                                           |
| F-6  | §16 out of scope  | Removes "Auth", "Persistence", "Dark mode toggle" — they move into Phase 2 scope                                                                                 | SPRINT-15                                                                                                |

### Audit verdict — is this spec still the right target?

**No.** Spec-1 has been completely delivered (every section, every checklist item, every acceptance criterion). It is **not** the right target for the next sprint, for three independent reasons:

1. **It's a finished phase (Phase 1).** Sprints 1.1 → 1.10 closed the loop. There is no in-flight work left in spec-1's Phase-1 surface area. **SPRINT-11, SPRINT-12, SPRINT-13, and SPRINT-14 (Phase 2 hardening tracks) are complete** — see §0.4–§0.5 and [`../../sprints/complete/`](../../sprints/complete/). **Phase 2 overall is not finished** — **SPRINT-15–16** are planned ([`../../sprints/planned/`](../../sprints/planned/)).
2. **It prescribes patterns the implementation has superseded in code.** C-2, C-4 (SPRINT-11) and C-1, C-3 (SPRINT-12) are fixed in production; the **spec text in §8/§15/§17 still shows the old prescription** as a historical record — do not reintroduce those patterns.
3. **It does not describe the system that exists.** The implementation already includes test-harness infrastructure (E-2, E-5, E-6), HTML-correctness fixes (D-2), Tailwind v4 syntax (D-1), and module extractions (E-3) that have no analog in the spec. A reader cannot use spec-1 to predict the shape of `lib/chat_app/`.

**Recommendation:** spec-1 should be **frozen** as a historical record (move to `docs/specs/complete/spec-1.md` — already in the audit's P0 backlog) and a new `docs/specs/active/spec-2.md` should be written that:

- **Folds in** the C-coded fixes from §17 (auth, supervised tasks, sanitized HTML, error channel, configurable model).
- **Promotes** what was §16 out-of-scope into the new in-scope (persistence, basic-auth gate, multi-conversation sidebar, settings drawer, copy/feedback, telemetry).
- **Codifies** the E-coded extensions (testability shims, `data-role` attributes, hero query-param override gated by env flag) so they stop being undocumented.
- **Reuses** the §1–§6 design surface unchanged — the visual UX is correct and shipped.

Until spec-2 is written, treat the planned sprint files (`docs/sprints/planned/SPRINT-14..16-*.md`), the **SPRINT-13** active record (`docs/sprints/active/SPRINT-13-hardening-architecture.md`), and the completed Phase 2 records (**SPRINT-11** and **SPRINT-12** in `docs/sprints/complete/`) as the de-facto target. They each cite the spec section they touch, so the gap is recoverable, but it is not yet a single navigable document.

---

## 18. Phase 3: UI Polish and Rebranding

### 18.1 Ad-hoc baseline update (2026-04-28)

The current UI no longer matches the original Phase 3 plan exactly because a manual polish pass shipped after SP-03-18 closed. These behaviors are now canonical and future Phase 3 work must preserve them:

- Desktop sidebar is collapsible and starts collapsed by default.
- Header text pills are gone; the current controls are a left hamburger toggle, a square `hero-pencil-square` new-chat button, and a right settings gear.
- The transient top model strip and API cost card were removed from the header/chat chrome.
- The named 4-theme selector is functional and persists through `data-theme` on `<html>` plus `localStorage`.
- The new-chat hero landing animation is intentionally more visible than the original sprint plan.
- The footer is now a larger professional section that lives below the initial chat viewport and is reached by scrolling a dedicated page shell.

Treat the items above as existing scope. Remaining sprint work should harden, test, and extend them rather than reintroducing the older UI.

**Branding Direction:**
- **App Name:** Threadworks AI
- **Design:** Elegant and editorial, unapologetically unique. Retain existing colors and fonts, ensuring proper contrast ratios, hover/action states, and readability.
- **Key UX Updates:**
  - Make the side panel with chats collapsible.
  - Remove the unnecessary API cost window below the header.
  - Move "+ New" and "Settings" actions to corners and convert them to icons.
  - Fix the theme selector to seamlessly switch between 4 distinct styles: Editorial (default), Swiss, Mid-Century Modern, and Techno-Brutalist.
  - Remove unnecessary up and down arrows (feedback) from message bubbles.
  - Add a footer section (product info, about the author, how it works, use cases, settings link, GitHub link, and contact form).

### SPRINT-17: Branding + Naming
**Goal:** Update all name, color, and identity references globally to establish the "Threadworks AI" brand.
**Deliverables:**
- Global renaming to "Threadworks AI" in HTML titles, wordmarks, and documentation.
- Validated and adjusted color variables in `foundation.css` to guarantee WCAG-compliant contrast ratios.
- Implementation of a footer for project identity. The original footer shipped in SP-03-17, and the current shipped variant is a larger below-the-fold author/project/link section rendered outside the initial chat viewport.
**Acceptance Criteria:**
- The page `<title>` and main `<p class="brand-wordmark">` render "Threadworks AI".
- The footer remains below the initial chat viewport and becomes visible only after scrolling the page shell.
- The shipped footer presents author/project copy plus LinkedIn, GitHub, and Portfolio link cards with visible hover/focus affordances.
**Complexity:** Low
**Risks:** Footer placement and page-shell scrolling must not regress transcript/composer layout on mobile devices.

### SPRINT-18: Bug Fixes
**Goal:** Address all issues identified in the "BROKEN / BUGGY" section of the audit.
**Deliverables:**
- Fixed composer textarea overflow.
- Corrected Tailwind opacity modifiers in flash components.
- Integrated error states into the semantic design system.
- Correct z-index stacking for header and sidebar.
**Acceptance Criteria:**
- The `<textarea>` in `chat_live.ex` scrolls vertically when content exceeds `192px` in height (using `overflow-y: auto`).
- Flash messages in `core_components.ex` use valid Tailwind syntax (`bg-[var(--status-error)]` without arbitrary `/` modifiers unless properly configured).
- Stream retry and rate limit alerts use `--status-error` and `--status-success` colors instead of hardcoded `red-500` or `emerald-500`.
- The sidebar correctly stacks beneath or alongside the header without z-index collisions (header uses `z-20`, sidebar uses `z-10` or a consistent layout).
**Complexity:** Low
**Risks:** Fixing overflow might introduce mobile layout shifts if not tested on iOS Safari.

### SPRINT-19: Component Polish
**Goal:** Improve `core_components.ex` and shared UI elements based on the audit's "IMPROVEMENT OPPORTUNITIES".
**Deliverables:**
- Migration of generic buttons to semantic utility classes.
- Replacement of raw text symbols with Heroicons.
- Tailwind Typography (`.prose`) color override for seamless dark mode support.
**Acceptance Criteria:**
- The "Regenerate" and "Copy" buttons use `icon-btn` styles, incorporating SVG Heroicons (`hero-arrow-path`, `hero-clipboard`), with `8px` padding, a `150ms` background transition, and an active scale-down effect.
- Sidebar "Rename" and "Delete" actions use `<.icon name="hero-pencil" />` and `<.icon name="hero-trash" />`.
- Markdown output inside `.ui-chat-message-assistant` inherits the parent text color (using `prose-p:text-inherit` or equivalent) across all themes.
**Complexity:** Medium
**Risks:** Overriding `.prose` globally might break specific markdown formatting (like inline code blocks) if not scoped carefully.

### SPRINT-20: Page-by-Page Polish
**Goal:** Harden and extend the structural UX improvements that are already partially shipped in the current app shell.

**Sprint repo mapping:** **SP-03-19A** (closed 2026-04-29, [`../../sprints/complete/SP-03-19A-desktop-layout.md`](../../sprints/complete/SP-03-19A-desktop-layout.md)) delivered automated regression and hardening for the default-collapsed desktop sidebar, header icon accessibility, absence of `data-usage-cost` / top model chrome, and page-shell/footer scroll invariants. Remaining items in this section (e.g. mobile drawer via **SP-03-19B**, theme-engine work via **SP-03-20**) are tracked in [`../../sprints/README.md`](../../sprints/README.md) and [`../../phases/phase-3.md`](../../phases/phase-3.md).

**Already done ad-hoc:** Desktop sidebar collapse, default-collapsed desktop state, header icon-only controls, removal of the top model strip and API cost card, a working 4-theme selector, the square pencil new-chat control, and the stronger hero landing animation are already live.
**Deliverables:**
- Regression coverage and layout hardening for the shipped collapsible sidebar component.
- Preserve removal of the top model strip and API cost tracker.
- Preserve and polish the shipped header icon controls (`hero-bars-3`, `hero-pencil-square`, `hero-cog-6-tooth`) rather than replacing them.
- Preserve and harden the shipped multi-theme selector bridging the UI and the design system themes.
- Preserve the dedicated page-shell scroll behavior that keeps the larger footer below the initial viewport.
**Acceptance Criteria:**
- The sidebar remains collapsed by default on desktop and still toggles via the header `hero-bars-3` control.
- No `data-usage-cost` element or top model badge is reintroduced.
- The header remains icon-led and retains the shipped square pencil new-chat control plus right-side settings gear.
- The theme toggle buttons continue to apply `"editorial"`, `"swiss"`, `"mid-century"`, and `"techno-brutalist"` data attributes to the `<html>` element and update `localStorage` across reloads and LiveView patches.
- The footer remains below fold and is reached by scrolling the page shell rather than by restoring the old root/body overflow lock.
**Complexity:** High
**Risks:** The remaining risk is not feature absence but accidental regression while refactoring layout, breakpoints, or theme plumbing.

### SPRINT-21: Empty / Loading / Error States
**Goal:** Make every transient state intentional, branded, and polished.
**Deliverables:**
- Premium skeleton loader or branded animation for the assistant's "thinking" state.
- Branded empty states for the sidebar (when no conversations exist).
- Properly formatted and padded UI alerts for configuration success/errors.
**Acceptance Criteria:**
- The typing indicator is replaced with a refined animation (e.g., a pulsing brand mark or a skeleton text block) rather than default `bg-accent-interactive` dots.
- A "No conversations yet" placeholder message appears in the sidebar when empty, styled with `text-foreground/50` and an illustrative SVG.
- "Settings saved" notifications utilize a `.alert-success` utility class with `12px` padding, border radius, and a subtle background tint, avoiding raw text blocks.
**Complexity:** Medium
**Risks:** Complex loading animations can cause high CPU usage or frame drops if not implemented with GPU-accelerated CSS properties.
