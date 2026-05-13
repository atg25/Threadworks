# Changelog

This project does not yet publish versioned releases. This file
summarizes the codebase as it exists today and will be updated going
forward in Keep-a-Changelog style.

## [Unreleased] — Current State (2026-04-24)

### Added (Sprint 15 — Feature Foundation: Persistence + Auth + First Controls, 2026-04-27)

- Added SQLite persistence via Ecto (`ChatApp.Repo`) with `conversations` + `messages` tables.
- Added `ChatApp.Conversations` boundary for `get_or_create/1`, message append/update, and destructive reset.
- Added basic-auth gate (env-driven) for non-localhost deployments.
- Added chat controls: "+ New" (reset), Stop (cancel stream), Regenerate (re-run last user turn).
- Added three-button theme toggle (system/light/dark) in the header rail.

### Changed (Sprint 15 — Feature Foundation: Persistence + Auth + First Controls, 2026-04-27)

- `ChatLive` now loads messages from SQLite on mount and persists user/assistant turns during streaming.
- CI runs `mix test.setup` to ensure migrations run before tests.

### Security (Sprint 15 — Feature Foundation: Persistence + Auth + First Controls, 2026-04-27)

- Added optional basic auth (`BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD`) to gate production access.

### Added (Sprint 14 — Hardening B: Tooling, Docs & Governance, 2026-04-26)

- Wired Vitest into `mix precommit` (runs `npm test` under `assets/`).
- Added/updated `@moduledoc` for key web modules and enabled `mix docs` via `:ex_doc` (dev-only).
- Removed the unused `:api` pipeline and documented the `generators:` config intent for Sprint 15.
- Added GitHub Actions CI workflow running `mix compile --warnings-as-errors`, `mix test --exclude real_api --exclude e2e`, and `npm test`.
- Added `LICENSE` (MIT) and SPDX license metadata (`package.licenses`) in `mix.exs`.

### Changed (Sprint 13 — Hardening A: Architecture & Internals, 2026-04-25)

- **H-1 closed** — Moved SSE leftover-line buffer from process dictionary (`Process.get/put(:sse_buf)`) into `req.private[:sse_buf]` via `Req.Request.put_private/3`. `ChatApp.OpenAI.stream/2` is now pure with respect to the calling process; no process-dictionary state.
- **H-2 closed** — Rewrote `ChatApp.Chat.upsert_assistant_message/2` from O(N²) (double traversal via `List.last` + `List.update_at`) to O(N) (single `Enum.reverse` pass). Added type guards (`is_list/is_binary`).
- **H-3 closed** — Moved `#scroll-to-bottom` click-handler binding from `onScroll()` into `mounted()` in `ChatScroll.js`; extracted `_updateDockVisibility()` helper called from both `mounted()` and `onScroll()`. Pill is now interactive and correctly hidden before the first scroll event.
- **H-4 closed** — Added structured `Logger.warning/error` calls on all three failure paths in `ChatApp.OpenAI`: non-2xx response, transport error, and rescue clause. No API key or message content is logged.
- **H-5 closed** — Replaced bare `Dotenvy.source!` call in `config/runtime.exs` dev block with a conditional load (only if `.env` exists), followed by a `case` that raises an instructive error (including `cp .env.example .env` hint) when `OPENAI_API_KEY` is unset.
- **H-6 closed** — Deleted the dead `handle_event("scroll_position", ...) when is_binary(at_bottom)` clause from `ChatAppWeb.ChatLive`. Single clause with `is_boolean` guard remains, with invariant comment.
- **H-7 closed** — Replaced list concatenation (`req_options ++ base_opts`) with `Keyword.merge(base_opts, req_options)` so override keys take precedence. Documented precedence in `ChatApp.OpenAI` `@moduledoc`.

### Security

- Verified `.env` was never committed via `git log --all --full-history -S "sk-proj-" -- .` scan (date: 2026-04-25). Rotated production OpenAI key as a precaution.

### Fixed

- Removed runtime `Mix.*` dependency from `ChatLive.mount/3`; `hero_state` override is now gated by `Application.get_env(:chat_app, :allow_hero_override, false)`.
- Hardened Markdown rendering by pre-escaping input HTML before parsing so assistant `<script>` payloads render as text.
- Made OpenAI model configurable via `config :chat_app, :openai_model, "gpt-4o"` and request-body lookup in `ChatApp.OpenAI`.
- Kept composer markup as a paired `<textarea>...</textarea>` with body interpolation (no invalid `value=` attribute).

### Added

- `ChatAppWeb.ChatLive` — single-page streaming chat console at `/`.
  - Hero intro (brand chip cluster, H2, sub, 3 proof-point cards) that
    collapses permanently on first send.
  - Auto-resizing composer (max 192 px), Enter-to-send, Shift+Enter for
    newline, disabled while streaming.
  - Streaming assistant bubbles with Markdown rendering (Earmark) and a
    typing-indicator pulse while `stream_buffer` is empty.
  - Auto-scroll viewport with a "scroll-to-bottom" CTA pill.
- `ChatApp.OpenAI` — `Req ~> 0.5` streaming client for
  `api.openai.com/v1/chat/completions`, hardcoded to `gpt-4o`.
- `ChatApp.OpenAI.SSE` — chunk-boundary-safe SSE line-splitting
  accumulator.
- `ChatApp.OpenAI.Stub` and `ChatApp.OpenAI.E2EStub` — two test doubles
  for unit and Wallaby E2E respectively.
- `ChatApp.Chat.upsert_assistant_message/2` — pure function used to
  accumulate streamed tokens into the last assistant message.
- `ChatApp.Markdown.to_html/1` — Earmark wrapper; input is HTML-escaped before Markdown rendering to prevent raw HTML injection in assistant bubbles.
- CSS architecture: `foundation.css` → `shell.css` → `utilities.css`
  → `chat.css`, loaded in that order from `app.css`, on top of Tailwind v4.
- Google Fonts: IBM Plex Sans, IBM Plex Mono, Fraunces, bound to CSS
  custom properties.
- LiveView JS hooks: `ChatScroll`, `ChatComposer`.
- Theme script (system / light / dark) wired up in `root.html.heex`
  (no visible toggle UI is rendered today).

### Removed

- Deleted scaffold-only `PageController`, `PageHTML`, and `page_html/home.html.heex`.
- Removed obsolete `Layouts.theme_toggle/1` helper from `ChatAppWeb.Layouts`.
- Trimmed unused `CoreComponents` helpers: `button/1`, `input/1`, `header/1`, `table/1`, `list/1`, and private `error/1`.
- Removed scaffold placeholder test `test/chat_app_web/controllers/page_controller_test.exs`.

### Tests

- ExUnit unit tests for `ChatApp.Chat`, `ChatApp.Markdown`, `ChatApp.OpenAI`,
  `ChatApp.OpenAI.SSE`.
- LiveView component/event tests for `ChatLive` (mount, events, bubbles).
- `Bypass`-based integration test of the OpenAI streaming client against
  a realistic SSE stub.
- Wallaby end-to-end feature tests against `ChatApp.OpenAI.E2EStub`,
  covering layout, hero, composer, multi-turn, scroll pill, fonts.
- CSS architecture regression test asserting import order and token
  presence.
- A single `@tag :real_api` smoke test (skipped in CI) that hits the
  live OpenAI API.

### Known gaps (see `docs/audit/` or the principal-engineer audit output)

- No auth and no conversation persistence.
- Generated `PageController`/`PageHTML`/`theme_toggle` components are
  orphaned dead code.
- `ChatAppWeb.CoreComponents` still contains daisyUI-dependent markup
  even though daisyUI is not installed.

### Changed (Unreleased — 2026-05-12)

- Refactored `ProductCard` component: extracted HEEx `ChatAppWeb.ProductCard` into `lib/chat_app_web/components/product_card_component.ex` and kept legacy wrapper `ChatAppWeb.Components.ProductCard` in `lib/chat_app_web/components/product_card.ex` to preserve compatibility.
- Hardened `ProductCard` against unsafe inputs: added `sanitize_href/1` and `sanitize_img_src/1`, escaped attribute values, added `aria-label` for accessibility, and improved `format_price/1` handling for Decimal/float/int/string inputs.
- Added unit, integration, and safety tests for `ProductCard` covering formatting, XSS-safety, and malicious href/img scenarios. Ran `mix format`.
