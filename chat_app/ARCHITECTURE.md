# Architecture

This document describes ChatApp as it exists in the codebase on 2026-04-24.
It is **descriptive** (what is), not **prescriptive** (what should be).
For planned changes see `CHANGELOG.md` and the QA audit.

---

## 1. Product shape

ChatApp is a single-page, single-session, anonymous streaming chat
console. One URL (`/`), one LiveView (`ChatAppWeb.ChatLive`), one in-memory
conversation per browser tab. There is no database, no user model, no
route other than `/`.

The full user story:

> 1. User visits `/`.
> 2. A hero intro animates in with three proof-point cards.
> 3. User types into the composer; the textarea auto-resizes up to 192 px.
> 4. User presses Enter (or clicks the send button).
> 5. The hero collapses, permanently.
> 6. The user's message appears as a right-aligned bubble.
> 7. A typing-indicator pulse appears on the assistant side.
> 8. OpenAI streams tokens; each token replaces the pulse with an
>    accumulating Markdown-rendered assistant bubble.
> 9. When the stream ends, the composer re-enables.
> 10. User scrolls up → a "↓ Scroll to bottom" pill appears.

Refresh the page and the conversation is gone. That is by design today.

---

## 2. Runtime topology

```
 ┌─────────────────────────────────────────────────────────────────────┐
 │                            Browser                                  │
 │  root.html.heex (html/body h-full, fonts, CSRF, theme JS)           │
 │  └── ChatAppWeb.ChatLive (HEEx, container div height:100%)          │
 │       └── LiveSocket ──────────────────────────────────────────┐    │
 │            hooks: ChatScroll, ChatComposer                      │    │
 └─────────────────────────────────────────────────────────────────│────┘
                                                                   │ WS / longpoll
                                                                   ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │           BEAM node — ChatApp.Application supervision tree          │
 │                                                                     │
 │   Supervisor (:one_for_one, name: ChatApp.Supervisor)               │
 │    ├── ChatAppWeb.Telemetry                                         │
 │    ├── DNSCluster (passive — no query configured today)             │
 │    ├── Phoenix.PubSub (name: ChatApp.PubSub — unused by the app)    │
 │    └── ChatAppWeb.Endpoint (plug_cowboy 2.7)                        │
 │          └── Plug pipeline → ChatAppWeb.Router                      │
 │                └── :browser pipeline                                │
 │                      └── live "/" → ChatAppWeb.ChatLive             │
 │                                                                     │
 │   LiveView-spawned, unsupervised:                                   │
 │     Task.start → ChatApp.OpenAI.stream/2                            │
 │                    └─ Req.post(…, into: SSE.parse_sse_chunk/3)      │
 │                        └─ send(lv_pid, {:stream_token, token})      │
 └─────────────────────────────────────────────────────────────────────┘
                                                                   │
                                                                   ▼
                         https://api.openai.com/v1/chat/completions
                           (stream: true, model: "gpt-4o")
```

---

## 3. Module map

### Domain (`lib/chat_app/`)

| Module                      | Purpose                                                         |
| --------------------------- | --------------------------------------------------------------- |
| `ChatApp`                   | Context namespace (placeholder).                                |
| `ChatApp.Application`       | OTP supervisor.                                                 |
| `ChatApp.Chat`              | Pure function(s) over the in-memory message list.               |
| `ChatApp.Markdown`          | Earmark wrapper, returns raw HTML binary.                       |
| `ChatApp.OpenAI`            | `stream/2` — fire-and-forget streaming HTTP client.             |
| `ChatApp.OpenAI.SSE`        | Chunk-boundary-safe SSE line-splitting accumulator.             |
| `ChatApp.OpenAI.Stub`       | Unit-test double (empty token, no `:stream_done`).              |
| `ChatApp.OpenAI.E2EStub`    | Wallaby double (canned two-token "Stub response.").             |

### Web (`lib/chat_app_web/`)

| Module                                | Purpose                                                 |
| ------------------------------------- | ------------------------------------------------------- |
| `ChatAppWeb.Endpoint`                 | HTTP + LiveView socket.                                 |
| `ChatAppWeb.Router`                   | One live route: `/` → `ChatLive`.                       |
| `ChatAppWeb.ChatLive`                 | The only page. State machine + render.                  |
| `ChatAppWeb.Layouts`                  | `app/1`, `flash_group/1`, `theme_toggle/1` (unused).    |
| `ChatAppWeb.CoreComponents`           | Generated `mix phx.new` kit. Largely unused by ChatLive.|
| `ChatAppWeb.{ErrorHTML,ErrorJSON}`    | Render-errors formatters.                               |
| `ChatAppWeb.Telemetry`                | Phoenix/BEAM metrics.                                   |
| `ChatAppWeb.Gettext`                  | i18n backend (no translations yet).                     |

### Frontend (`assets/`)

| File                            | Purpose                                         |
| ------------------------------- | ----------------------------------------------- |
| `js/app.js`                     | LiveSocket setup, hook registration.            |
| `js/hooks/ChatScroll.js`        | Viewport auto-scroll + scroll-to-bottom pill.   |
| `js/hooks/ChatComposer.js`      | Textarea auto-resize + Enter-to-send.           |
| `css/app.css`                   | Import order gate: foundation → shell → utilities → chat. |
| `css/foundation.css`            | Design tokens (CSS custom properties).          |
| `css/shell.css`                 | Shell / nav utilities.                          |
| `css/utilities.css`             | `theme-*`, `tier-*`, `focus-ring`.              |
| `css/chat.css`                  | `ui-chat-*` component classes.                  |

---

## 4. Data model

There is no persistent data model. The entire conversation lives in
`socket.assigns`:

```elixir
%{
  messages:      [%{role: :user | :assistant, content: String.t()}],
  input:         String.t(),      # current textarea value
  is_sending:    boolean(),       # true between send and :stream_done
  stream_buffer: String.t(),      # accumulated tokens for the in-flight reply
  at_bottom:     boolean(),       # pushed from ChatScroll
  hero_state:    boolean()        # false after first send, forever
}
```

The message list is a plain list, in chronological order. Streaming
uses `ChatApp.Chat.upsert_assistant_message/2` to either replace the last
assistant message (when we're mid-stream) or append a new one (when the
last message is the user's).

No message IDs. No timestamps. No authors beyond `:user` / `:assistant`.

---

## 5. Streaming sequence

```
User keydown "Enter"
  │
  │ ChatComposer hook → requestSubmit()
  ▼
phx-submit "send_message" {input}
  │
  ▼ ChatLive.handle_event/3
    messages ++= user_msg
    is_sending = true
    stream_buffer = ""
    hero_state = false
    Task.start(fn ->
      openai_module().stream(messages, self())
    end)
  │
  ▼ (task)
    Req.post(..., into: parse_sse_chunk)
        for each chunk:
          SSE.parse_sse_chunk(chunk, acc, lv_pid)
             → send(lv_pid, {:stream_token, token}) per delta
    on :ok with 2xx  → send(lv_pid, :stream_done)
    on :ok non-2xx   → send(lv_pid, {:stream_error, "HTTP N"})
    on {:error, _}   → send(lv_pid, {:stream_error, ...})
    on rescue        → send(lv_pid, {:stream_error, Exception.message(e)})
  │
  ▼ ChatLive.handle_info/2
    {:stream_token, t} → buffer <>= t; upsert assistant bubble
    :stream_done       → is_sending = false; stream_buffer = ""
    {:stream_error, r} → append "Error: r" as assistant msg; is_sending = false
```

---

## 6. CSS architecture

Tailwind v4 is loaded first, then the four custom CSS files are imported
in this exact order (tested by `css_architecture_test.exs`):

1. `foundation.css` — design tokens (`--space-*`, `--color-*`,
   `--chat-composer-*`, etc.)
2. `shell.css` — outer shell / navigation utilities.
3. `utilities.css` — `theme-*`, `tier-*`, `focus-ring`.
4. `chat.css` — `ui-chat-*` component classes
   (`ui-chat-composer-plane`, `ui-chat-transcript-plane`,
   `ui-chat-message-user`, `ui-chat-scroll-cta`, etc.)

All three Google Fonts families are declared on `html` via CSS custom
properties. Height propagates via `height:100%` on `<html>` → `<body>`
→ the container `<div>` that `ChatLive` sets via its
`container: {:div, style: "height: 100%;"}` option → the `<section>`
which is a 3-row CSS grid: header / viewport / composer rail.

---

## 7. Testing strategy

| Layer                 | Tool                         | What it covers                                   |
| --------------------- | ---------------------------- | ------------------------------------------------ |
| Pure functions        | ExUnit                       | `Chat.upsert_assistant_message/2`, `SSE.*`, `Markdown.to_html/1`. |
| OpenAI client (mocked)| ExUnit + `Req.Test` plug     | Error paths, missing key, connection refused.    |
| OpenAI client (HTTP)  | ExUnit + Bypass              | Realistic SSE streaming, chunk splits, HTTP 4xx/5xx. |
| LiveView mount        | `Phoenix.LiveViewTest`       | Initial assigns, hero state, composer presence.  |
| LiveView events       | `Phoenix.LiveViewTest`       | Full state machine (send, blank, double, stream). |
| LiveView render       | `Phoenix.LiveViewTest`       | Bubble classes, Markdown → HTML.                 |
| CSS architecture      | ExUnit file-content asserts  | Import order, token declarations, dark variant.  |
| End-to-end            | Wallaby + headless Chrome    | Real server, real browser, stubbed OpenAI.       |
| Real OpenAI (optional)| ExUnit `@tag :real_api`      | One-shot smoke test, not run in CI.              |
| JS hooks              | Vitest + jsdom (configured)  | *No tests committed yet.*                        |

---

## 8. Key design decisions

1. **LiveView `container:` override** (`chat_live.ex:16-17`). The default
   LiveView container is a `<div data-phx-main>` with no height style. To
   make `h-full` cascade from `<html>` to the grid `<section>`, the
   container div needs `height:100%`. The `ChatAppWeb, :live_view` macro
   doesn't forward this option, so `ChatLive` bypasses it and uses
   `Phoenix.LiveView` directly, replicating the imports it needs.
2. **Process-dictionary SSE buffer** (`openai.ex:33-43`). Req's `into:`
   callback must preserve the `{req, resp}` acc tuple as its return
   value. The SSE line-splitting accumulator is therefore stored in the
   per-Task process dictionary. This works because each call lives in a
   fresh `Task.start` process. *(Flagged in the QA audit for refactor.)*
3. **Two tiers of OpenAI stubs**. Unit tests need to drive stream timing
   manually (to exercise race conditions), so `ChatApp.OpenAI.Stub` does
   not send `:stream_done`. Wallaby tests need deterministic replies, so
   `ChatApp.OpenAI.E2EStub` sends two tokens + `:stream_done`
   synchronously.
4. **Markdown trust boundary** (`markdown.ex:15-23`). `Earmark.as_html`
   runs with `escape: false` and is emitted via `Phoenix.HTML.raw/1`.
   The module comment explicitly calls this a trusted-input boundary —
   which is safe only if the prompt is also trusted. **Today it is not**,
   because a user can ask the model to echo HTML. *(QA audit: flagged as
   the primary XSS risk.)*
5. **Hero is one-way**. Once `hero_state: false` is set on first send, it
   never flips back to `true`, even if messages are somehow cleared.
   This is a product decision, pinned by a unit test.
6. **No persistence is a feature today**. Rebuild + refresh is the
   only "new conversation" affordance. Persistence is listed as
   explicitly out of scope in `docs/specs/spec-1.md §16`.

---

## 9. Deployment shape (intended, not yet exercised)

- `mix release` builds a self-contained tarball under `_build/prod/rel`.
- The release is started with `PHX_SERVER=true bin/chat_app start`.
- `config/runtime.exs` reads `SECRET_KEY_BASE`, `OPENAI_API_KEY`,
  `PHX_HOST`, `PORT`, `DNS_CLUSTER_QUERY` from the environment.
- Assets are digested via `MIX_ENV=prod mix assets.deploy`
  (tailwind + esbuild with `--minify` + `phx.digest`).
- Plug.SSL / `force_ssl` is commented out in `config/runtime.exs`;
  enable before public exposure.

There is no Dockerfile, no CI config, no Fly.io / release.exs template
in the repo today.

---

## 10. Known risks (short)

See the QA audit for full detail. The three most important:

1. `Mix.env()` at runtime in `ChatLive.mount/3` will crash in a release.
2. `ChatApp.Markdown` renders model output as raw HTML — stored XSS.
3. No auth + no rate limiting + a live OpenAI key = public billing risk
   the moment the app touches the internet.
