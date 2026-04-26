# ChatApp

![CI](https://github.com/atg25/Threadworks/actions/workflows/ci.yml/badge.svg)

A single-page streaming AI chat console built on Phoenix LiveView. A user
types a prompt, the server proxies it to the OpenAI Chat Completions API
with `stream: true`, and assistant tokens are streamed back into the
LiveView in real time. Markdown is rendered with Earmark; the hero intro
collapses permanently on first send. State lives entirely in the LiveView
socket — no database, no auth, no conversation persistence.

This is the minimum viable shape of a larger "one compact system" product:
today it does chat only.

---

## Tech stack

| Layer          | Tool                                              |
| -------------- | ------------------------------------------------- |
| Language       | Elixir `~> 1.15`                                  |
| Web            | Phoenix `~> 1.7`, Phoenix LiveView `~> 0.20`      |
| HTTP server    | `plug_cowboy ~> 2.7`                              |
| HTTP client    | `Req ~> 0.5` (streams via `into:` callback)       |
| Markdown       | `Earmark ~> 1.4`                                  |
| JSON           | `Jason ~> 1.4`                                    |
| Env loading    | `Dotenvy ~> 0.8` (dev only)                       |
| CSS            | Tailwind v4 (standalone CLI) + custom token layer |
| JS bundler     | esbuild `0.25.4`                                  |
| Fonts          | IBM Plex Sans, IBM Plex Mono, Fraunces            |
| Unit tests     | ExUnit + `Phoenix.LiveViewTest`                   |
| HTTP tests     | `Bypass` (git: `PSPDFKit-labs/bypass`)            |
| E2E tests      | `Wallaby ~> 0.30` + headless Chrome               |
| JS hooks tests | Vitest `^4.1.5` + jsdom                           |

---

## Prerequisites

- Elixir 1.15+ / Erlang/OTP 26+ (`asdf install elixir 1.15.x` or similar)
- Node.js 20+ (for Vitest; Phoenix itself does not require Node)
- Headless Chrome + chromedriver (for E2E tests)
  - Easiest: `npx puppeteer browsers install chrome@stable chromedriver@stable`
    — the test config auto-discovers the Puppeteer cache on macOS arm64.
  - Or set `CHROMEDRIVER_PATH` and `CHROME_BINARY_PATH` explicitly.
- An OpenAI API key with access to `gpt-4o`.

---

## Setup

```bash
# 1. Clone and enter
git clone <repo-url> && cd chat_app

# 2. Create your .env from the template
cp .env.example .env
# edit .env and paste your OPENAI_API_KEY

# 3. Install Elixir deps + JS/CSS tooling
mix setup
```

`mix setup` runs `deps.get`, installs the Tailwind and esbuild binaries,
and compiles assets.

---

## Running

### Dev server

```bash
mix phx.server
# → http://localhost:4000
```

Or with an IEx shell:

```bash
iex -S mix phx.server
```

### Tests

```bash
mix test                       # unit + LiveView + integration + E2E
mix test --exclude real_api    # skip the live-OpenAI smoke test (default)
mix test --only real_api       # hit the real OpenAI API (requires valid key)
mix precommit                  # full Elixir suite + Vitest JS hook suite
```

`mix precommit` runs the full Elixir suite plus the Vitest JS hook suite.

JavaScript hook tests (Vitest):

```bash
cd assets
npm install       # first run only
npm test           # one-shot
npm run test:watch # watch mode
```

Run the JS hook tests directly via `cd assets && npm test`, or as part of `mix precommit`.

#### CI

On every push to `main` and on every pull request, CI runs `mix deps.get`, `mix compile --warnings-as-errors`, `mix test --exclude real_api --exclude e2e`, then `npm install` and `npm test` in `assets/`.

### Production build

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

---

## Environment variables

| Variable             | Required           | Purpose                                                               | Example                                                        |
| -------------------- | ------------------ | --------------------------------------------------------------------- | -------------------------------------------------------------- |
| `OPENAI_API_KEY`     | yes (dev + prod)   | Bearer token for `api.openai.com`                                     | `sk-proj-…`                                                    |
| `SECRET_KEY_BASE`    | yes (prod only)    | Signs cookies / LiveView session — generate with `mix phx.gen.secret` | 64+ random chars                                               |
| `PHX_SERVER`         | yes (prod)         | Set to `true` in a release to actually boot the HTTP endpoint         | `true`                                                         |
| `PHX_HOST`           | recommended (prod) | Canonical host in generated URLs                                      | `chat.example.com`                                             |
| `PORT`               | optional           | HTTP port (default `4000`)                                            | `8080`                                                         |
| `DNS_CLUSTER_QUERY`  | optional (prod)    | DNS-based clustering query string                                     | `myapp.internal`                                               |
| `CHROMEDRIVER_PATH`  | optional (tests)   | Override chromedriver binary for Wallaby E2E                          | `/usr/local/bin/chromedriver`                                  |
| `CHROME_BINARY_PATH` | optional (tests)   | Override Chrome binary for Wallaby E2E                                | `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` |

See `.env.example` for a fillable template.

### Rotating the OpenAI key

Revoke the old key in the [OpenAI API keys console](https://platform.openai.com/api-keys).
Generate a replacement key in the same console.
Paste the new value into local `.env` only, and never commit secrets to git.

---

## Project structure

```
chat_app/
├── assets/                        Frontend source
│   ├── css/
│   │   ├── app.css                entry; imports the 4 layers + Tailwind
│   │   ├── foundation.css         design tokens (CSS custom properties)
│   │   ├── shell.css              shell / nav utilities
│   │   ├── utilities.css          theme-*, tier-*, focus-ring
│   │   └── chat.css               ui-chat-* component classes
│   ├── js/
│   │   ├── app.js                 LiveSocket + hooks registration
│   │   └── hooks/
│   │       ├── ChatScroll.js      viewport auto-scroll + pill
│   │       └── ChatComposer.js    textarea auto-resize + Enter-to-send
│   └── package.json               Vitest / Tailwind plugins
├── config/
│   ├── config.exs                 shared (esbuild, tailwind, logger)
│   ├── dev.exs                    watchers, code reloader
│   ├── test.exs                   :openai_module → Stub, Wallaby setup
│   ├── prod.exs                   cache manifest, force_ssl
│   └── runtime.exs                loads .env (dev), reads OPENAI_API_KEY
├── lib/
│   ├── chat_app.ex                context placeholder
│   ├── chat_app/
│   │   ├── application.ex         OTP supervisor
│   │   ├── chat.ex                pure: upsert_assistant_message/2
│   │   ├── markdown.ex            Earmark wrapper
│   │   └── openai/
│   │       ├── openai.ex          Req streaming client
│   │       ├── sse.ex             SSE line-splitting accumulator
│   │       ├── stub.ex            unit-test double
│   │       └── e2e_stub.ex        Wallaby deterministic double
│   └── chat_app_web/
│       ├── endpoint.ex
│       ├── router.ex              live "/", ChatLive, :index
│       ├── live/chat_live.ex      the one page
│       └── components/
│           ├── layouts.ex         layouts + flash + theme toggle
│           ├── layouts/root.html.heex
│           └── core_components.ex generated (mostly unused today)
├── test/
│   ├── chat_app/                  OpenAI, SSE, Markdown, Config tests
│   ├── chat_app_web/
│   │   ├── live/                  ChatLive unit + events + bubbles
│   │   ├── features/              Wallaby E2E
│   │   └── css_architecture_test.exs
│   └── support/
│       ├── conn_case.ex
│       └── feature_case.ex
└── docs/
    ├── specs/spec-1.md            original product spec
    └── sprints/complete/          sprint-1.1 … sprint-1.10
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system-level design
discussion, data model, and key decisions.

---

## API surface

This application exposes exactly one HTTP endpoint:

| Method | Path | Auth | Description                                                                                                             |
| ------ | ---- | ---- | ----------------------------------------------------------------------------------------------------------------------- |
| `GET`  | `/`  | none | Renders `ChatAppWeb.ChatLive`, establishes a LiveView socket over `/live` (WebSocket with long-poll fallback at 2.5 s). |

There is no JSON API, no webhook, and no admin route.

LiveView events received from the browser:

| Event             | Payload                       | Meaning                                                                 |
| ----------------- | ----------------------------- | ----------------------------------------------------------------------- |
| `send_message`    | `%{"input" => String.t()}`    | Submit a user message (trimmed; ignored if blank or already streaming). |
| `update_input`    | `%{"input" => String.t()}`    | Keystroke sync for `phx-change`.                                        |
| `scroll_position` | `%{"at_bottom" => boolean()}` | Pushed by `ChatScroll` on scroll.                                       |

LiveView → self messages:

| Message                     | Meaning                                       |
| --------------------------- | --------------------------------------------- |
| `{:stream_token, binary()}` | A delta chunk from OpenAI — append to buffer. |
| `:stream_done`              | 2xx end-of-stream; clear `is_sending`.        |
| `{:stream_error, binary()}` | Any non-2xx / exception / transport failure.  |

---

## License

This project is released under the [MIT License](LICENSE).
