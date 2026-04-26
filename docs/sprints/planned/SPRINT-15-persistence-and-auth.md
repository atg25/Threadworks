---
status: planned
---

# SPRINT 15 — Feature Foundation: Persistence + Auth + First Controls

**Status:** PLANNED
**Created:** 2026-04-24
**Activated:** TBD
**Completed:** TBD

## Goal
Bridge the largest "demo → product" gap by giving conversations persistence (SQLite via Ecto), gating non-localhost deploys with basic auth, and shipping the two stop/theme controls that depend on Sprint 12's `Task.Supervisor` and Sprint 14's clean docs.

**Total effort:** ~14 hours (1 × L + 1 × L + 1 × M + 2 × S)
**Parallelizable:** TASK 5 (theme-toggle UI) is fully independent. TASK 4 (stop/regenerate) depends on TASK 1's persistence. TASK 3 (basic auth) is independent of TASK 1 and TASK 2 — can run in parallel. TASK 1 → TASK 2 must be sequenced.

---

## TDD Test Specification

Per-task descriptions below contain each task's primary tests. This section adds the upfront layer table, the E2E coverage (positive + ≥2 negative), and explicit pure-unit / static checks. Per-task tests inside each TASK block are the source of truth for shape; this section is additive.

### Layer summary

| Layer | Tool | Test files | Tasks |
| --- | --- | --- | --- |
| Unit | ExUnit + `Ecto.Changeset` | `test/chat_app/conversations/conversation_test.exs` (new), `test/chat_app/conversations/message_test.exs` (new) | 1 |
| Integration (DB) | ExUnit + `Ecto.Adapters.SQL.Sandbox` | `test/chat_app/conversations_test.exs` | 1, 4 |
| Integration (LiveView + DB) | `Phoenix.LiveViewTest` + `DataCase` | `test/chat_app_web/live/chat_live_persistence_test.exs`, `test/chat_app_web/live/chat_live_stop_regen_test.exs` | 2, 4, 5 |
| Integration (auth pipeline) | `Phoenix.ConnTest` | `test/chat_app_web/basic_auth_test.exs` | 3 |
| E2E | Wallaby + ChromeDriver (`@moduletag :e2e`) | `test/chat_app_web/features/chat_e2e_test.exs` | 2, 3, 4, 5 |
| Static | ripgrep, `mix ecto.migrate`, `mix compile --warnings-as-errors` | CI step / PR description | 1, 2, 3 |

### Unit tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Conversation.changeset/2 requires session_id` | `Conversation.changeset(%Conversation{}, %{title: "x"})` | `changeset.valid?` is false; `errors[:session_id]` exists. | TASK 1 — schema accepting orphan rows. |
| `Conversation.changeset/2 enforces unique session_id constraint at the schema layer` | Insert one conversation with `session_id: "abc"`; build a second changeset with the same id and run `Repo.insert/1`. | First insert returns `{:ok, _}`; second returns `{:error, %Ecto.Changeset{errors: [session_id: {_, [constraint: :unique, ...]}]}}`. | TASK 1 — duplicate active conversations per session, breaking `get_or_create/1`. |
| `Message.changeset/2 rejects roles other than :user / :assistant` | `Message.changeset(%Message{}, %{conversation_id: 1, role: :system, content: "x"})` | `changeset.valid?` is false; `errors[:role]` mentions `:inclusion`. | TASK 1 — system or function-call roles silently persisted, polluting prompt context. |
| `Message.changeset/2 requires content (non-empty string allowed)` | `Message.changeset(%Message{}, %{conversation_id: 1, role: :user})` (no content). | Invalid; `errors[:content]` exists. Empty string `""` is accepted (assistant-message placeholder before tokens). | TASK 1 — nil content reaching the OpenAI body builder. |
| `cents_to_dollars/1 formats to two decimals with leading $` | `0`, `7`, `1234`, `100_000` | `"$0.00"`, `"$0.07"`, `"$12.34"`, `"$1000.00"`. | TASK 2 (header rail cost) — formatting drift across locales. |
| `auth_basic_when_configured/2 is a no-op when both env vars are unset` | Build a conn; `Application.delete_env(:chat_app, :basic_auth_user)` and `:basic_auth_password`; call the plug. | Returned conn equals input conn (no `halt`, no `WWW-Authenticate` header set). | TASK 3 — accidentally locking dev / test environments. |
| `drop_last_assistant/1 removes only the trailing assistant entry` | `[%{role: :user}, %{role: :assistant}]`, `[%{role: :user}]`, `[]`, `[%{role: :assistant}, %{role: :user}]`. | Returns `[%{role: :user}]`, `[%{role: :user}]`, `[]`, `[%{role: :assistant}, %{role: :user}]` (no change when last is :user). | TASK 4 — `Regenerate` accidentally deleting the user message. |

### Integration tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `get_or_create/1 is idempotent` | Call twice with `"sess-1"`. | Both return the same `%Conversation{id: id}`; `Repo.aggregate(Conversation, :count)` is 1. | TASK 1 — double-insert under race; 2 conversation rows per session. |
| `append_message/3 returns inserted message with id` | `append_message(conv.id, :user, "hi")`. | `{:ok, %Message{id: int, role: :user, content: "hi", conversation_id: ^conv.id}}`. | TASK 1 — silent failure due to missing `:conversation_id` in cast list. |
| `update_assistant_message/2 mutates content in place` | Insert a placeholder assistant message; `update_assistant_message(id, "new buffer")`. | `Repo.get!(Message, id).content == "new buffer"`. | TASK 2 — append-only writes that quadratically explode the messages table. |
| `delete_conversation/1 cascades to messages` | Conv with 3 messages; delete the conv. | `Repo.aggregate(Message, :count, where: [conversation_id: ^id]) == 0`. | TASK 1 — orphan messages outliving their conversation. |
| `messages are restored on remount` | Submit a message, drive `:stream_token` + `:stream_done`; kill the LiveView; mount a new one with same session id. | `assigns.messages` length matches what was sent; assistant content equals the streamed buffer. | TASK 2 — refresh wipes the conversation. |
| `new_conversation event clears messages and shows hero` | Send a message, then trigger `phx-click="new_conversation"`. | After event: `length(assigns.messages) == 0`; `assigns.hero_state == true`; new conversation row exists in DB (the prior was reset/replaced). | TASK 2 — reset that wipes messages from memory but leaves stale rows in DB (or vice versa). |
| `empty assistant content is persisted as ""` | Drive `:stream_done` immediately with an empty buffer. | `Repo.get!(Message, id).content == ""`. | TASK 2 — persisting `nil` and crashing the next mount. |
| `per-conversation isolation: two session_ids do not share messages` | Mount as `"sess-A"`, send 2 messages. Mount as `"sess-B"`. | `assigns.messages` for `"sess-B"` is `[]`. | TASK 2 — leakage via shared `Repo` query. |
| `throttled writes: 100 tokens result in fewer than 100 Repo updates` | Stub a stream that emits 100 tokens; attach `:telemetry.attach` on `[:chat_app, :repo, :query]`. | Update count ≤ 25 (10/token threshold + final). | TASK 2 — un-debounced writes saturating SQLite. |
| `:stream_done forces a final write` | 5 tokens then `:stream_done`. | Final `Repo.get!(Message, id).content` equals the full buffer. | TASK 2 — debounce timer dropping the final fragment. |
| `GET / returns 200 when basic_auth_user is unset` | Conn; both env vars unset. | Status 200; HTML contains the chat composer. | TASK 3 — auth on by default in dev. |
| `GET / returns 401 when configured and no Authorization header is sent` | Set `:basic_auth_user`/`:basic_auth_password`; send a plain `get(conn, "/")`. | Status 401; `WWW-Authenticate` header present. | TASK 3 — protection only checked on POST, not GET. |
| `GET / returns 200 when correct Authorization header is sent` | Set credentials; send `Plug.BasicAuth.encode_basic_auth(user, pass)` header. | Status 200. | TASK 3 — credential comparison broken (e.g. case-sensitive header name). |
| `GET / returns 401 with wrong password` | Set credentials; send wrong password header. | Status 401; constant-time comparison observed (no early return on first byte mismatch — guaranteed by `Plug.Crypto.secure_compare/2`). | TASK 3 — bypass via timing / wrong comparison. |
| `stop_generation kills the streaming task and clears state` | Submit; receive 1 token; trigger `phx-click="stop_generation"`. | `assigns.stream_task_pid == nil`; `assigns.is_sending == false`; partial assistant message persists in `assigns.messages` AND in the DB. | TASK 4 — Stop swallowing the partial output, OR leaving a zombie task. |
| `regenerate after stream_done removes the last assistant message and re-streams from the prior user message` | Run a complete turn; trigger `phx-click="regenerate"`. | `length(assigns.messages)` decreases by 1; corresponding DB row deleted; a new streaming task is spawned with the original user prompt. | TASK 4 — Regenerate replaying the wrong message, OR appending instead of replacing. |
| `regenerate while is_sending is a no-op` | Submit; before `:stream_done`, dispatch `regenerate`. | Assigns unchanged; no new task spawned; no DB delete. | TASK 4 — racing tasks producing duplicate streams. |
| `header rail contains three theme buttons with non-empty aria-labels` | `live(conn, "/")`; render. | `Floki.find(html, "[data-phx-theme]") |> length() == 3`; every match's `aria-label` is non-empty. | TASK 5 — partial render, accessibility regression. |

### E2E tests (Wallaby — `@moduletag :e2e`)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Positive — refresh restores conversation | Open `/`; send `"hello"`; await `:stream_done`; reload page. | Both user and assistant bubbles re-appear with the same text; hero is hidden. | TASK 2 — DB or session_id wiring drift. |
| Negative — basic auth blocks anonymous request when configured | Set `BASIC_AUTH_USER` / `BASIC_AUTH_PASSWORD` in the test env; navigate Wallaby to `/` with no credentials. | Browser receives 401 (Wallaby surfaces as a navigation error); `data-chat-state` element is never reached. | TASK 3 — auth bypassed by LiveView socket upgrade. |
| Negative — Stop button cancels mid-stream and partial content remains | Open `/`; submit a long prompt against an E2E stub that streams 1 token / 200ms; click Stop after first token visible. | Streaming halts within 500ms; partial assistant text remains visible; refresh continues to show it (DB persisted). | TASK 4 — Stop wiping the partial OR not actually stopping. |
| Negative — Regenerate without a prior assistant turn is a no-op (no DB churn) | Open `/`; without sending anything, force the `regenerate` event via JS console. | No new task spawned; `Repo.aggregate(Message, :count) == 0`; no client-side error. | TASK 4 — `regenerate` crashing on empty conversation. |
| Negative — Theme toggle survives page reload | Open `/`; click dark; reload. | `<html data-theme="dark">` is set on reload (localStorage round-trip works). | TASK 5 — JS hook regression on the `phx:set-theme` listener. |

### Static / CI checks (no test framework)

| Check | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `mix ecto.migrate` is idempotent | Run twice in a row in `MIX_ENV=test`. | Second run prints `Already up`; exit 0. | TASK 1 — non-idempotent migration breaking CI re-runs. |
| `ChatApp.Repo` is the first child of the application supervisor | `rg "ChatApp\\.Repo" chat_app/lib/chat_app/application.ex` and inspect order. | Repo appears before `ChatAppWeb.Endpoint` in the children list. | TASK 1 — Repo started after Endpoint causing first-mount crashes. |
| `unique_index(:conversations, [:session_id])` exists exactly once | `rg "unique_index\\(:conversations" chat_app/priv/repo/migrations/` | Exactly one match. | TASK 1 — duplicate index, OR forgotten index allowing duplicates. |
| Basic auth never enabled in dev/test by default | `rg "basic_auth_user|basic_auth_password" chat_app/config/{dev,test}.exs` | Zero matches. | TASK 3 — accidentally shipping locked-down dev. |
| `.env.example` documents all new env vars | `rg "DATABASE_PATH|POOL_SIZE|BASIC_AUTH_USER|BASIC_AUTH_PASSWORD" chat_app/.env.example` | Four matches. | TASKS 1+3 — silent operator surprise. |
| `mix compile --warnings-as-errors` clean after schema add | Run after TASK 1. | Exit 0. | TASK 1 — unused alias / unused schema warnings. |

---

## Tasks

### TASK 1 — Add Ecto + SQLite + conversation/message schemas

**Context:**
Today the entire conversation is held in the LiveView socket and disappears on reconnect. F-1 is the single largest "demo → product" milestone in the audit. SQLite is chosen for v1 because it requires zero infrastructure (one file in `priv/repo/`), has no external service dependency, and is sufficient for a single-node deployment. Postgres is the natural successor when multi-node lands. (Audit F-1, L.)

**Exact Scope:**

- `chat_app/mix.exs`: add to `deps/0`:
  ```elixir
  {:ecto_sql, "~> 3.10"},
  {:ecto_sqlite3, "~> 0.13"}
  ```
  Run `mix deps.get`. Verify exact current versions via `mix hex.info ecto_sql` and `mix hex.info ecto_sqlite3` and pin the latest stable major.

- `chat_app/config/config.exs`:
  - Add: `config :chat_app, ecto_repos: [ChatApp.Repo]`.
  - Keep the `generators: [timestamp_type: :utc_datetime]` line uncommented now (Sprint 14 TASK 3 left it gated behind a comment; remove the comment, the config is now used).

- `chat_app/config/dev.exs`:
  ```elixir
  config :chat_app, ChatApp.Repo,
    database: Path.expand("../priv/repo/chat_app_dev.db", __DIR__),
    pool_size: 5,
    show_sensitive_data_on_connection_error: true
  ```

- `chat_app/config/test.exs`:
  ```elixir
  config :chat_app, ChatApp.Repo,
    database: Path.expand("../priv/repo/chat_app_test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5
  ```

- `chat_app/config/runtime.exs` (inside the `if config_env() == :prod` block, after the existing endpoint config):
  ```elixir
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise "DATABASE_PATH is missing — point at a writable .db path."

  config :chat_app, ChatApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))
  ```

- `chat_app/.env.example`: add `# DATABASE_PATH=/var/lib/chat_app/chat_app.db` and `# POOL_SIZE=5` under the `### Required in prod only` block.

- `chat_app/lib/chat_app/repo.ex`:
  ```elixir
  defmodule ChatApp.Repo do
    use Ecto.Repo,
      otp_app: :chat_app,
      adapter: Ecto.Adapters.SQLite3
  end
  ```

- `chat_app/lib/chat_app/application.ex`: add `ChatApp.Repo` as the FIRST child in the supervisor list (before Telemetry), so migrations and queries are available before the endpoint accepts requests.

- `chat_app/lib/chat_app/conversations.ex` (new):
  ```elixir
  defmodule ChatApp.Conversations do
    @moduledoc """
    Persistence boundary for conversations and messages. Pure-function callers
    only — no LiveView assigns leak into this module.
    """

    import Ecto.Query
    alias ChatApp.Repo
    alias ChatApp.Conversations.{Conversation, Message}

    def get_or_create(session_id) when is_binary(session_id) do
      case Repo.get_by(Conversation, session_id: session_id) do
        nil  -> %Conversation{session_id: session_id} |> Repo.insert!()
        conv -> conv
      end
    end

    def list_messages(conversation_id) do
      Message
      |> where(conversation_id: ^conversation_id)
      |> order_by(asc: :inserted_at, asc: :id)
      |> Repo.all()
    end

    def append_message(conversation_id, role, content)
        when is_integer(conversation_id) and role in [:user, :assistant] and is_binary(content) do
      %Message{}
      |> Message.changeset(%{conversation_id: conversation_id, role: role, content: content})
      |> Repo.insert!()
    end

    def update_assistant_message(message_id, content) when is_integer(message_id) and is_binary(content) do
      Repo.get!(Message, message_id)
      |> Message.changeset(%{content: content})
      |> Repo.update!()
    end

    def reset_conversation(session_id) when is_binary(session_id) do
      Repo.delete_all(from c in Conversation, where: c.session_id == ^session_id)
    end
  end
  ```

- `chat_app/lib/chat_app/conversations/conversation.ex` (new):
  ```elixir
  defmodule ChatApp.Conversations.Conversation do
    use Ecto.Schema
    import Ecto.Changeset

    schema "conversations" do
      field :session_id, :string
      field :title, :string
      has_many :messages, ChatApp.Conversations.Message
      timestamps(type: :utc_datetime)
    end

    def changeset(conv, attrs) do
      conv
      |> cast(attrs, [:session_id, :title])
      |> validate_required([:session_id])
      |> unique_constraint(:session_id)
    end
  end
  ```

- `chat_app/lib/chat_app/conversations/message.ex` (new):
  ```elixir
  defmodule ChatApp.Conversations.Message do
    use Ecto.Schema
    import Ecto.Changeset

    @roles ~w(user assistant)a

    schema "messages" do
      field :role, Ecto.Enum, values: @roles
      field :content, :string
      belongs_to :conversation, ChatApp.Conversations.Conversation
      timestamps(type: :utc_datetime)
    end

    def changeset(msg, attrs) do
      msg
      |> cast(attrs, [:conversation_id, :role, :content])
      |> validate_required([:conversation_id, :role, :content])
      |> validate_inclusion(:role, @roles)
    end
  end
  ```

- `chat_app/priv/repo/migrations/20260424120000_create_conversations.exs` (new):
  ```elixir
  defmodule ChatApp.Repo.Migrations.CreateConversations do
    use Ecto.Migration

    def change do
      create table(:conversations) do
        add :session_id, :string, null: false
        add :title, :string
        timestamps(type: :utc_datetime)
      end

      create unique_index(:conversations, [:session_id])

      create table(:messages) do
        add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
        add :role, :string, null: false
        add :content, :text, null: false
        timestamps(type: :utc_datetime)
      end

      create index(:messages, [:conversation_id])
    end
  end
  ```

- `chat_app/test/support/conn_case.ex`: add `Ecto.Adapters.SQL.Sandbox.checkout(ChatApp.Repo)` and the standard `:manual` mode setup.

- `chat_app/test/support/data_case.ex` (new): standard Ecto.DataCase template (copy from any Phoenix Ecto scaffold).

- `chat_app/test/chat_app/conversations_test.exs` (new): full unit tests for `Conversations` — `get_or_create/1`, `list_messages/1`, `append_message/3`, `update_assistant_message/2`, `reset_conversation/1`. At least 8 tests covering: idempotent `get_or_create`, message ordering, role validation, cascade delete, content roundtrip with Markdown, conversation_id uniqueness, etc.

- `chat_app/mix.exs`: update the `setup` alias to include `ecto.create` and `ecto.migrate`:
  ```elixir
  setup: ["deps.get", "ecto.create", "ecto.migrate", "assets.setup", "assets.build"]
  ```
  Add a new `test.setup` alias used in CI: `["ecto.create --quiet", "ecto.migrate --quiet", "test"]`. Update CI (`.github/workflows/ci.yml`) to run `mix test.setup` instead of `mix test`.

**Acceptance Criteria:**
- [ ] `mix ecto.create && mix ecto.migrate` succeeds in dev and creates `priv/repo/chat_app_dev.db`.
- [ ] `mix ecto.create --quiet && mix ecto.migrate --quiet && mix test` succeeds in test.
- [ ] `Conversations.get_or_create/1` returns the same conversation row across calls with the same session_id.
- [ ] `Conversations.append_message/3` rejects roles other than `:user` and `:assistant`.
- [ ] Deleting a conversation cascades to messages.
- [ ] All ≥8 new unit tests pass.
- [ ] `ChatApp.Repo` is the first child of the application supervisor.
- [ ] `mix precommit` exits 0.
- [ ] `.env.example` documents `DATABASE_PATH` and `POOL_SIZE`.

**Edge Cases to Handle:**
- SQLite file path doesn't exist on first boot — `mix ecto.create` creates it; on first prod boot, the `DATABASE_PATH` directory must be writable (documented in README).
- Two LiveViews mount with the same session_id (browser dup tab) — `get_or_create/1` is idempotent; both share the same conversation row.
- Migration runs against an already-migrated DB — `ecto.migrate` is idempotent.
- Concurrent message inserts within one conversation — SQLite's WAL mode is enabled by default in `ecto_sqlite3`; serialization is fine for v1's load.

**Do NOT do:**
- Do NOT wire the LiveView to the Repo in this task — that is TASK 2.
- Do NOT add Postgres as an option in `mix.exs` deps.
- Do NOT add full-text search (FTS5) on messages — out of scope for v1.
- Do NOT add Ecto changesets for analytics or metrics tables.
- Do NOT pre-populate seed data.

**Effort:** L
**Depends on:** Sprint 14 TASK 3 (the `generators:` decision; this task assumes the line is kept).

---

### TASK 2 — Wire `ChatLive` to load and save through `Conversations`

**Context:**
TASK 1 lands the schema; this task makes the LiveView actually use it. After this lands, refreshing the page restores the conversation. (Audit F-1, second half.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/live/chat_live.ex`:

  - In `mount/3`:
    - Generate `session_id` once per LiveView (already done in Sprint 12 TASK 3); ensure it persists across reconnects by reading from `socket.assigns[:session_id]` if present, else using the connect_params token. Phoenix LiveView's `get_connect_params/1` exposes a stable client-side session id if provided. For v1, accept that a hard refresh resets the session_id; full session-cookie wiring is in Sprint 16.
    - On `connected?(socket) == true`:
      - `conversation = ChatApp.Conversations.get_or_create(session_id)`
      - `messages = ChatApp.Conversations.list_messages(conversation.id) |> Enum.map(&%{role: &1.role, content: &1.content})`
      - `hero_state = messages == []` (only show hero if conversation is empty)
    - On the disconnected mount (HTTP fetch): use `messages: []` and `hero_state: true` to keep first-paint fast.

  - In `handle_event("send_message", ...)`:
    - After the rate-limit check (Sprint 12 TASK 3), BEFORE spawning the streaming task:
      - `ChatApp.Conversations.append_message(socket.assigns.conversation_id, :user, text)`
    - Add `assigns.conversation_id` to the assigns map.

  - In `handle_info({:stream_token, token}, socket)`:
    - When the assistant message goes from absent to first-token: insert a placeholder row and store its id in `assigns.assistant_message_id`.
    - When updating: `ChatApp.Conversations.update_assistant_message(assigns.assistant_message_id, buffer)`.
    - To avoid one Repo write per token (which would be costly), debounce: write only every 10 tokens OR every 250ms, whichever fires first. Use `Process.send_after(self(), :persist_assistant_buffer, 250)` and a flag in assigns. Final write happens unconditionally on `:stream_done`.

  - In `handle_info(:stream_done, socket)`:
    - Final `update_assistant_message/2` call with the full buffer.
    - Set `assistant_message_id: nil`.

  - Add a new event `handle_event("new_conversation", _, socket)`:
    - Calls `ChatApp.Conversations.reset_conversation(session_id)` and `ChatApp.Conversations.get_or_create(session_id)`.
    - Resets all assigns to mount defaults.

  - Add a "New conversation" button in the header rail (`ui-chat-header-surface` div, currently empty). Single button: "+ New" with `phx-click="new_conversation"`. Use plain Tailwind utility classes consistent with the existing header rail.

- `chat_app/test/chat_app_web/live/chat_live_persistence_test.exs` (new): at least 6 tests:
  - `"messages are restored on remount"` — submit a message, drive `:stream_token` + `:stream_done`, kill the LiveView, mount a new one with the same session id, assert the messages are visible.
  - `"new_conversation event clears messages and shows hero"` — submit, then click new, assert hero is back.
  - `"empty assistant content (no tokens before stream_done) is persisted as empty string"` — drive `:stream_done` immediately, assert DB row exists with `content: ""`.
  - `"per-conversation isolation: two session_ids do not share messages"`.
  - `"throttled writes: 100 tokens result in fewer than 100 Repo updates"` — count via `:telemetry.attach` on `[:chat_app, :repo, :query]`.
  - `":stream_done forces a final write"` — drive 5 tokens then `:stream_done`, verify the final stored content equals the full buffer.

**Acceptance Criteria:**
- [ ] On mount, `messages` are populated from the DB.
- [ ] On send, the user message is persisted before the streaming task starts.
- [ ] During streaming, the assistant message is upserted in the DB at most once per 250ms / 10 tokens.
- [ ] On `:stream_done`, a final write captures the complete buffer.
- [ ] "New conversation" button in the header rail clears messages and resets hero.
- [ ] Hard refresh of the page shows the same conversation (modulo the v1 session_id-on-mount limitation, documented in README).
- [ ] All ≥6 new tests pass.
- [ ] All previously-passing LiveView tests pass (existing tests use `:openai_module` stubs and don't touch the DB; ensure `Ecto.Adapters.SQL.Sandbox.checkout` is in `ConnCase`'s setup).
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- LiveView crashes mid-stream — the assistant message in the DB is whatever the last debounced write captured; the next mount restores up to that point. Acceptable for v1; idempotent retries are F-10 in Sprint 16.
- User submits message while DB write is in flight — the `is_sending` guard already prevents this.
- DB is read-only / disk full — Repo raises; LiveView crashes; user sees the LiveView reconnect flash. Document.
- A conversation has 10,000 messages — `list_messages/1` loads them all on mount. For v1 this is acceptable (no user will hit it). Pagination is a Sprint 17+ task.

**Do NOT do:**
- Do NOT add a "delete conversation" UX with confirmation in this task — keep "New" as a destructive overwrite per the audit.
- Do NOT build the multi-conversation sidebar — F-3 in Sprint 16.
- Do NOT add token-usage tracking — F-8 in Sprint 16.
- Do NOT add user accounts — auth is TASK 3 of this sprint, but only basic-auth (option A).

**Effort:** L
**Depends on:** TASK 1.

---

### TASK 3 — Add basic-auth gate (Option A: shared secret)

**Context:**
The audit's F-2 specifies "must land before any public deployment." Option A (BASIC_AUTH_USER/BASIC_AUTH_PASSWORD) is the simplest gate. Pair with Sprint 12's session rate limit and one anonymous attacker can no longer drain credits. (Audit F-2, S.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/router.ex`:
  - Add a new pipeline plug above `:browser`:
    ```elixir
    pipeline :basic_auth do
      plug :auth_basic_when_configured
    end
    ```
  - Define `auth_basic_when_configured/2` at the bottom of the module:
    ```elixir
    defp auth_basic_when_configured(conn, _opts) do
      user = Application.get_env(:chat_app, :basic_auth_user)
      pass = Application.get_env(:chat_app, :basic_auth_password)

      if is_binary(user) and is_binary(pass) and user != "" and pass != "" do
        Plug.BasicAuth.basic_auth(conn, username: user, password: pass)
      else
        conn
      end
    end
    ```
  - Update the `scope "/"` block to `pipe_through [:basic_auth, :browser]`.

- `chat_app/config/runtime.exs`: in the prod block, add:
  ```elixir
  config :chat_app, :basic_auth_user, System.get_env("BASIC_AUTH_USER")
  config :chat_app, :basic_auth_password, System.get_env("BASIC_AUTH_PASSWORD")
  ```
  In `dev.exs`: do NOT set these — auth is bypassed when unset. In `test.exs`: do NOT set these.

- `chat_app/.env.example`:
  ```
  # --- Recommended in prod for any non-localhost deploy ---
  # BASIC_AUTH_USER=admin
  # BASIC_AUTH_PASSWORD=use-a-long-random-string
  ```

- `chat_app/test/chat_app_web/router_test.exs` or new `chat_app/test/chat_app_web/basic_auth_test.exs`: 4 tests:
  - `"GET / returns 200 when basic_auth_user is unset"`.
  - `"GET / returns 401 when basic_auth is configured and no Authorization header is sent"`.
  - `"GET / returns 200 when correct Authorization header is sent"`.
  - `"GET / returns 401 with wrong password"`.
  - Use `Application.put_env`/`on_exit` to set/unset the credentials per test.

- `chat_app/README.md`: add a "Production deployment" subsection explaining BASIC_AUTH_USER/PASSWORD as the v1 access gate, with a one-line `htpasswd -nB admin` style suggestion for generating a strong password (or `openssl rand -base64 32`).

**Acceptance Criteria:**
- [ ] `Plug.BasicAuth.basic_auth/2` is invoked only when both env vars are set and non-empty.
- [ ] When unset (dev / test), the LiveView mounts without 401.
- [ ] When set, requests without Authorization header receive 401.
- [ ] When set, requests with correct credentials receive 200.
- [ ] All 4 new tests pass.
- [ ] No code outside `router.ex` and `runtime.exs` references basic auth.
- [ ] `README.md` has the Production deployment section.

**Edge Cases to Handle:**
- Only one of the two env vars is set — auth is BYPASSED (the function checks both); the README must warn against this.
- Constant-time comparison: `Plug.BasicAuth` already uses `Plug.Crypto.secure_compare/2` internally.
- The auth flash interferes with the LiveView's flash group — it does not; `Plug.BasicAuth` returns 401 before LiveView mounts.

**Do NOT do:**
- Do NOT implement option B (magic-link email auth) — deferred indefinitely; v1 ships with shared-secret only.
- Do NOT add a logout flow — basic auth doesn't have one in HTTP.
- Do NOT add per-user accounts or roles.
- Do NOT store BASIC_AUTH_PASSWORD anywhere except as an env var.
- Do NOT add a CSRF bypass for BasicAuth-protected routes — the CSRF protection is unaffected.

**Effort:** S
**Depends on:** None.

---

### TASK 4 — Stop / regenerate controls

**Context:**
With `Task.Supervisor` from Sprint 12 TASK 1, cancellation is implementable. "Stop generating" and "Regenerate last response" are table-stakes for any chat product. (Audit F-5, S.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/live/chat_live.ex`:

  - Add `handle_event("stop_generation", _, socket)`:
    - If `socket.assigns.stream_task_pid` is alive: `Process.exit(pid, :shutdown)`.
    - Send a `{:stream_stopped}` self-message that sets `is_sending: false`, `stream_buffer: ""`, `stream_task_pid: nil`. The partial assistant message stays in `messages` (and in the DB from TASK 2).

  - Add `handle_info({:stream_stopped}, socket)` matching the above.

  - Add `handle_event("regenerate", _, socket)`:
    - If `is_sending` is true: ignore.
    - Find the last assistant message in `assigns.messages`; if absent, ignore.
    - Drop the last assistant message from `assigns.messages` (and delete the corresponding DB row via `Conversations.delete_message/1` — add this function in Sprint 15 TASK 1 if not yet present, else add it here as a one-liner).
    - Resubmit the last user message via the same path as `send_message`, including the rate-limit check.

  - Update the render function:
    - When `is_sending: true`, show a "Stop" button in the same dock as the scroll pill (or in the composer's send-button slot — replace the send icon with a "■ Stop" while streaming). Choose the composer-slot approach to avoid layout shifts.
    - When the last message is `:assistant` AND `is_sending: false` AND there has been at least one user-assistant exchange, show a "Regenerate" button below the assistant bubble (or in the composer area as a secondary button).

- `chat_app/lib/chat_app/conversations.ex`: add `delete_message/1`:
  ```elixir
  def delete_message(message_id) when is_integer(message_id) do
    Repo.get!(Message, message_id) |> Repo.delete!()
  end
  ```

- `chat_app/test/chat_app_web/live/chat_live_stop_regen_test.exs` (new): 5 tests:
  - `"stop_generation kills the streaming task"` — submit, send a token, click stop, assert `stream_task_pid` is nil and `is_sending` is false.
  - `"stop_generation preserves the partial assistant message in messages and DB"`.
  - `"regenerate after stream_done removes the last assistant message"`.
  - `"regenerate while is_sending is a no-op"`.
  - `"regenerate triggers a new stream with the same prior user message"`.

**Acceptance Criteria:**
- [ ] "Stop" button visible only while `is_sending: true`.
- [ ] "Regenerate" button visible only when the last message is assistant AND `is_sending: false`.
- [ ] Clicking Stop terminates the supervised task and clears `is_sending`.
- [ ] Clicking Regenerate drops the last assistant message (in memory and DB) and re-streams from the last user message.
- [ ] Rate limit check applies to Regenerate.
- [ ] All 5 new tests pass.
- [ ] No layout shifts when the buttons appear/disappear (use `min-height` on their container).

**Edge Cases to Handle:**
- Stop clicked after `:stream_done` has already arrived — `Process.alive?/1` returns false; no-op.
- Regenerate clicked when the conversation has zero messages — early-return; no DB call.
- Regenerate clicked when the last message is a user message (orphaned because of a prior stop without a rewrite) — drop the user message? For v1: NO. Treat orphaned user messages as immutable; Regenerate is a no-op in this case. Document.
- The stopped task's last `:stream_token` arrives after `:stream_stopped` — handle in `handle_info({:stream_token, ...})` by checking `is_sending: false` and ignoring.

**Do NOT do:**
- Do NOT implement "edit and resend" — separate feature.
- Do NOT implement infinite-retry — F-10 in Sprint 16.
- Do NOT show a confirmation dialog for Stop or Regenerate.
- Do NOT add a keyboard shortcut for Stop (out of scope).

**Effort:** S
**Depends on:** Sprint 12 TASK 1 (`Task.Supervisor`), Sprint 15 TASK 2 (DB-backed messages).

---

### TASK 5 — Theme-toggle UI in the header rail

**Context:**
Theme JS (`root.html.heex` lines 18-36) is wired to localStorage and `data-theme` attributes, but there is no UI driver. After Sprint 12 deletes the daisyUI-flavored `Layouts.theme_toggle/1`, the page has no way to switch themes. This task ships a custom three-button toggle in the empty header rail. (Audit F-7, S.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Inside the `<div class="ui-chat-header-surface ..." data-chat-surface-header="true" ...>` (lines 120-125), add the toggle as the only child:
    ```heex
    <div role="group" aria-label="Theme" class="flex items-center gap-1 rounded-full border border-foreground/10 bg-background/50 p-1 backdrop-blur-sm">
      <button
        type="button"
        aria-label="Use system theme"
        data-phx-theme="system"
        phx-click={JS.dispatch("phx:set-theme")}
        class="ui-chat-theme-btn flex h-6 w-6 items-center justify-center rounded-full text-xs text-foreground/60 hover:text-foreground"
      >☼</button>
      <button
        type="button"
        aria-label="Use light theme"
        data-phx-theme="light"
        phx-click={JS.dispatch("phx:set-theme")}
        class="ui-chat-theme-btn flex h-6 w-6 items-center justify-center rounded-full text-xs text-foreground/60 hover:text-foreground"
      >○</button>
      <button
        type="button"
        aria-label="Use dark theme"
        data-phx-theme="dark"
        phx-click={JS.dispatch("phx:set-theme")}
        class="ui-chat-theme-btn flex h-6 w-6 items-center justify-center rounded-full text-xs text-foreground/60 hover:text-foreground"
      >●</button>
    </div>
    ```
  - Add `alias Phoenix.LiveView.JS` near the other aliases (line 28-ish). It is intentionally absent today; needed now.
  - The three glyphs (`☼ ○ ●`) are placeholder Unicode. If the team wants Heroicon equivalents, replace with `<.icon name="hero-computer-desktop" />` etc. — but that requires re-importing `ChatAppWeb.CoreComponents.icon/1` which the current ChatLive does not import. Decision: ship Unicode for v1 to keep the LiveView module's import surface small. Document.

- `chat_app/assets/css/chat.css`: optional polish — add a `:where([data-theme="dark"]) .ui-chat-theme-btn[data-phx-theme="dark"]` rule that highlights the active theme button. Out of scope to spec exactly; the dev agent picks tasteful styling.

- `chat_app/test/chat_app_web/live/chat_live_test.exs`: add 3 tests:
  - `"header rail contains three theme buttons"` — assert `Floki.find(html, "[data-phx-theme]") |> length == 3`.
  - `"each theme button has a non-empty aria-label"`.
  - `"each theme button has phx-click=phx:set-theme"` (verified via `data-phx-click` attribute on rendered HTML — the JS module produces a known string; Phoenix's test helper exposes the dispatch shape).

- `chat_app/test/chat_app_web/features/chat_e2e_test.exs`: add ONE Wallaby feature test that clicks the dark button and asserts `<html data-theme="dark">` is set (verifies the existing JS wiring still works end-to-end).

**Acceptance Criteria:**
- [ ] Three buttons render in the header rail with `data-phx-theme="system"|"light"|"dark"`.
- [ ] Clicking each button dispatches `phx:set-theme` (verified by E2E test).
- [ ] After clicking dark, `<html>` has `data-theme="dark"`.
- [ ] After clicking system, `data-theme` attribute is removed from `<html>`.
- [ ] localStorage `phx:theme` reflects the choice (existing JS handles this).
- [ ] All 3 unit tests + 1 E2E test pass.
- [ ] No new daisyUI classes are referenced.
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- User has prior `localStorage.phx:theme = "dark"` — page loads in dark mode (existing JS handles this on initial render); the toggle UI is purely additive.
- Theme buttons clicked before WebSocket connect — `JS.dispatch` works regardless of LiveView connection state; verified.
- Touch devices — buttons are 24×24 px which is below the 44px iOS guideline. For v1 acceptable; mobile polish is a follow-up.

**Do NOT do:**
- Do NOT bring back `Layouts.theme_toggle/1` (deleted in Sprint 12).
- Do NOT persist theme on the server — localStorage is the source of truth.
- Do NOT add an auto-detect-OS-changes listener beyond what `root.html.heex` already wires.
- Do NOT pull in any icon library.

**Effort:** S
**Depends on:** Sprint 12 TASK 4 (deletion of `theme_toggle/1`).

---

## DEFERRED TO SPRINT 16

- **F-3 Multi-conversation sidebar:** depends on TASK 1 + TASK 2 of this sprint; sidebar UX is its own milestone.
- **F-4 System prompt + model picker:** depends on Sprint 11 TASK 4 (configurable model) and a settings UI; bundled with F-6, F-8, F-9 in Sprint 16.
- **F-6 Copy + feedback controls on assistant bubbles:** depends on persistence (this sprint) for the feedback store.
- **F-8 Token / cost accounting:** depends on persistence + configurable model; bundled in Sprint 16.
- **F-9 Markdown code-block polish:** purely visual; bundled in Sprint 16.
- **F-10 Server-side streaming retry semantics:** depends on Sprint 13 TASK 4 (Logger) and Sprint 12 TASK 1 (TaskSupervisor); bundled in Sprint 16.

## SPRINT RISKS

- **SQLite write contention** under high streaming throughput: SQLite's WAL mode handles single-writer concurrency well, but a runaway test or production bug could lock. Mitigation: the debounced write strategy in TASK 2 caps writes at ~4/sec.
- **`get_or_create/1` race** when two processes mount simultaneously with the same session_id: the unique index on `session_id` causes one insert to fail. The dev agent must handle the `Ecto.Constraint` error and re-fetch. Add this to the `get_or_create/1` implementation.
- **Basic auth + LiveView WebSocket**: the `:browser` pipeline runs on the initial GET only; WebSocket upgrades go through a different path (`/live/websocket`) that does NOT include `:basic_auth`. For v1 this is acceptable — the WebSocket handshake validates the same session cookie set during the BasicAuth-protected GET. If the team needs to lock the socket too, it is a follow-up. Document this in the README.
- **Migration drift between dev and prod**: SQLite file location is parameterized; CI runs migrations on a fresh DB every time. Acceptable for v1.
- **Theme-toggle Unicode glyphs feel cheap** (TASK 5): purely cosmetic; ship and revisit.
- **Regenerate without a prior user message** edge case (TASK 4): documented as a no-op; the UX is "do nothing." Confirm with product if a different behavior is desired.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:
- [ ] All five tasks pass their acceptance criteria.
- [ ] `mix precommit` exits 0.
- [ ] `cd assets && npm test` exits 0.
- [ ] `mix test --exclude real_api` exits 0.
- [ ] CI (`.github/workflows/ci.yml`) is green on a final PR.
- [ ] A user can: refresh the page mid-conversation and see all prior messages; click "+ New" and start fresh; click Stop while streaming; click Regenerate after a response; switch themes from the header.
- [ ] `README.md` documents `DATABASE_PATH`, `BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD`, and the production deployment subsection.
- [ ] `CHANGELOG.md` `[Unreleased]` documents this sprint's `### Added`, `### Changed`, `### Security` blocks.
- [ ] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict
TBD

## Completion Notes
TBD
