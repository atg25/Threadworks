---
status: planned
---

# SPRINT 16 — Feature Velocity: Sidebar, Settings, Polish

**Status:** PLANNED
**Created:** 2026-04-24
**Activated:** TBD
**Completed:** TBD

## Goal
Convert the persistence + auth platform from Sprint 15 into product surface area: a multi-conversation sidebar, a settings drawer with model + system-prompt + temperature, hover controls on assistant bubbles, code-block polish, token / cost accounting, and bounded retry semantics.

**Total effort:** ~14 hours (4 × M + 2 × S)
**Parallelizable:** TASK 1 (sidebar) is the structural change every other task assumes — sequence first. TASKS 2, 3, 4, 5, 6 are independent of each other once TASK 1 is in.

---

## TDD Test Specification

Per-task descriptions below contain each task's primary tests. This section adds the upfront layer table, the E2E coverage (positive + ≥2 negative), and explicit pure-unit / static checks. Per-task tests inside each TASK block are the source of truth for shape; this section is additive.

### Layer summary

| Layer | Tool | Test files | Tasks |
| --- | --- | --- | --- |
| Unit | ExUnit + `Ecto.Changeset` | `test/chat_app/conversations/conversation_test.exs` (extended), `test/chat_app/conversations/usage_record_test.exs` (new), `test/chat_app/markdown_test.exs` (extended), `test/chat_app/openai_retry_test.exs` (new pure helpers) | 1, 2, 4, 5, 6 |
| Integration (DB + LiveView) | `Phoenix.LiveViewTest`, `DataCase`, `:telemetry.attach` | `test/chat_app_web/live/chat_live_sidebar_test.exs` (new), `test/chat_app_web/live/chat_live_settings_test.exs` (new), `test/chat_app_web/live/chat_live_feedback_test.exs` (new), `test/chat_app_web/live/chat_live_retry_test.exs` (new) | 1, 2, 3, 5, 6 |
| Integration (HTTP / SSE) | `Bypass`, `Req.Test` | `test/chat_app/openai_test.exs` (extended), `test/chat_app/openai_retry_test.exs` | 2, 5, 6 |
| Hooks (JS unit) | Vitest + jsdom | `assets/test/hooks/Clipboard.test.js`, `assets/test/hooks/PromptOnEvent.test.js` | 1, 3 |
| E2E | Wallaby + ChromeDriver (`@moduletag :e2e`) | `test/chat_app_web/features/chat_e2e_test.exs` (extended) | 1, 2, 3, 4 |
| Static | ripgrep, `mix ecto.migrate`, `mix compile --warnings-as-errors` | CI step / PR description | 1, 2, 4, 5 |

### Unit tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `auto_title_from_first_message/1 trims to 60 chars` | A 200-char user message. | Returned title is exactly 60 chars; no trailing punctuation orphans (final char isn't a partial multi-byte rune). | TASK 1 — sidebar showing 200-char wrapped titles. |
| `auto_title_from_first_message/1 collapses whitespace` | `"  hello\n\n   world  "`. | `"hello world"`. | TASK 1 — newline characters bleeding into the sidebar HTML. |
| `Conversation.changeset/2 rejects unknown model values` | `Conversation.changeset(conv, %{model: "fake-gpt-99"})`. | `valid?` is false; `errors[:model]` mentions `:inclusion`. | TASK 2 — typo in model name silently sent to OpenAI (which 400s). |
| `Conversation.changeset/2 rejects temperature outside [0.0, 2.0]` | `temperature: -0.1`, then `2.1`. | Both invalid; `errors[:temperature]` references `:greater_than_or_equal_to` / `:less_than_or_equal_to`. | TASK 2 — out-of-range temperature crashing OpenAI request. |
| `Conversation.changeset/2 rejects system_prompt longer than 4000 chars` | A 4001-char binary. | `valid?` is false; `errors[:system_prompt]` mentions `:length`. | TASK 2 — runaway memory / token cost from giant system prompts. |
| `Markdown.to_html wraps a fenced elixir block in .ui-code-block with data-language=elixir` | ```` ```elixir\nIO.puts(\"hi\")\n``` ```` | Output contains `<div class="ui-code-block" data-language="elixir">` with a header span containing `elixir` and a `<pre><code class="elixir">` body. | TASK 4 — wrapper missing for valid fences. |
| `Markdown.to_html unlabeled fence yields data-language=text` | ```` ```\nplain\n``` ```` | Output contains `data-language="text"`. | TASK 4 — `nil` rendered into the attribute. |
| `Markdown.to_html does NOT wrap inline code` | `` `print("hi")` `` (single backtick). | Output contains `<code>` but no `<div class="ui-code-block">`. | TASK 4 — over-eager wrapping breaking inline code styling. |
| `Markdown.to_html with multiple code blocks wraps each independently` | Two distinct fences in one message. | Two `<div class="ui-code-block">` siblings, each with its own data-language and copy button. | TASK 4 — first-block-only regression. |
| `record_usage cost computation with gpt-4o pricing` | `prompt_tokens: 1_000_000`, `completion_tokens: 500_000`, `model: "gpt-4o"`, prices `{2_50, 10_00}` cents per 1M. | `estimated_cost_cents == 250 + 500 == 750` (rounded to nearest cent). | TASK 5 — off-by-1000 multiplication errors silently overcharging users. |
| `record_usage with unknown model logs warning and stores cost = 0` | `model: "fake-gpt-99"`. | Insert succeeds with `estimated_cost_cents: 0`; `capture_log/1` contains `"unknown model"`. | TASK 5 — silent 0-cost on every conversation. |
| `cents_to_dollars/1 formatting` | `0`, `7`, `1234`. | `"$0.00"`, `"$0.07"`, `"$12.34"`. | TASK 5 — locale or float-arithmetic drift. |
| `backoff_ms increases between retries` | `0`, `1`, `2`. | `250`, `500`, `1000`. | TASK 6 — flat backoff causing thundering retries. |
| `drop_last_assistant/1 only drops a trailing assistant entry` | `[user, assistant]`, `[user]`, `[]`. | `[user]`, `[user]`, `[]`. | TASK 6 — `:stream_retrying` deleting the user message. |

### Integration tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `sidebar lists all conversations for the session` | Insert 3 conversations for `"sess-A"` and 1 for `"sess-B"`; mount as `"sess-A"`. | Sidebar `[data-conversation-id]` element count is 3; ids match the inserted rows. | TASK 1 — leakage across sessions. |
| `new_conversation creates a row and switches to it` | Mount with one existing conv; click "+ New". | A new conversation row is in DB; `assigns.current_conversation_id` equals the new id; `assigns.messages == []`. | TASK 1 — "+ New" appearing to work but not changing the active id. |
| `switch_conversation loads its messages` | Two convs with distinct messages; click the inactive one in the sidebar. | After event, `assigns.messages` reflects the clicked conv; sidebar's active styling moves. | TASK 1 — switching that mounts state but doesn't load messages. |
| `delete_conversation removes the row and switches to the next` | Three convs; delete the active one. | DB count drops to 2; `assigns.current_conversation_id` is now the next-most-recent. | TASK 1 — leaving `current_conversation_id` pointing at a deleted row. |
| `deleting the only conversation creates a fresh one` | One conv; delete it. | DB count is 1 (a new empty conv); `assigns.messages == []`. | TASK 1 — empty sidebar with no recovery path. |
| `first user message auto-titles the conversation` | Send `"What is OTP?"` as the first message in a fresh conv. | After `:stream_done`: `Repo.get!(Conversation, id).title == "What is OTP?"` (≤60 chars). | TASK 1 — Untitled forever in the sidebar. |
| `toggle_settings opens and closes the drawer` | Click the ⚙ button; click again. | After first click: `assigns.settings_open == true`; drawer DOM present. After second: `false`; drawer absent. | TASK 2 — drawer stuck open / closed after click. |
| `save_settings persists model + system_prompt + temperature` | Submit form with `{model: "gpt-4o-mini", system_prompt: "Be terse.", temperature: "0.4"}`. | `Repo.get!(Conversation, id)` has matching field values; `assigns.current_conversation` is reloaded; flash `"Settings saved"`. | TASK 2 — form bypassed by missing changeset cast. |
| `send_message uses the saved settings` | Save `{system_prompt: "Be terse.", temperature: 0.4, model: "gpt-4o-mini"}`; submit `"hello"`; capture `Req.Test` body. | Body's `model == "gpt-4o-mini"`; `messages` first entry is `%{role: "system", content: "Be terse."}`; `temperature == 0.4`. | TASK 2 — settings UI visible but never reaching the request. |
| `send_message without saved settings omits temperature and system role` | Fresh conv; submit `"hello"`. | Body's `model` falls back to `Application.get_env(:chat_app, :openai_model, ...)`; no `temperature` key; no `role: "system"` entry. | TASK 2 — defaults polluting the request body with nils. |
| `feedback event emits telemetry with rating + conversation_id` | Click ▲ button on assistant bubble; `:telemetry.attach` on `[:chat_app, :feedback]`. | Handler runs once with metadata `%{conversation_id: ^id, message_index: ^idx, rating: "up"}`. | TASK 3 — silent feedback events with no observability. |
| `feedback event sets a flash` | Click ▼. | `Phoenix.Flash.get(view.flash, :info) == "Thanks for the feedback."`. | TASK 3 — UX feedback missing. |
| `XSS protection from Sprint 11 TASK 2 is preserved through the wrapper` | Markdown ```` ```\n<script>alert(1)</script>\n``` ```` | Rendered HTML contains `&lt;script&gt;`; no literal `<script>` substring; `.ui-code-block` wrapper is present. | TASK 4 — wrapping accidentally re-enabling raw HTML. |
| `transport error retries up to 2 times` | Bypass returns `{:error, :closed}` twice, then 200 with a normal stream. | LiveView ultimately receives `:stream_done`; log shows two retry warnings. | TASK 6 — retries silently disabled. |
| `3rd transport error escalates to :stream_error` | Bypass returns `{:error, :closed}` on every attempt. | LiveView receives `:stream_error` after the 3rd attempt; partial assistant message has been cleared. | TASK 6 — infinite retry loop. |
| `4xx response does NOT retry` | Bypass returns 401. | `:stream_error` arrives immediately; log contains exactly one entry, no retry warnings. | TASK 6 — wasted retries on auth failures (and rate-limit headers). |
| `5xx response retries` | Bypass returns 500 once, then 200. | `:stream_done` arrives; one retry warning logged. | TASK 6 — over-eager classification of 5xx as fatal. |
| `:stream_retrying clears the partial assistant message in DB and assigns` | Drive 3 tokens, then `:stream_retrying`. | `assigns.stream_buffer == ""`; partial DB row deleted; transient error in `assigns.errors`. | TASK 6 — duplicate-prefix artifact. |
| `usage_for_conversation sums all records` | Insert 3 usage_records with `total_tokens: [100, 200, 300]` and `estimated_cost_cents: [1, 2, 3]`. | `usage_for_conversation(id) == %{total_tokens: 600, total_cost_cents: 6}` (or whatever the agreed shape is). | TASK 5 — wrong aggregation field. |

### Hook tests (Vitest + jsdom)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Clipboard hook writes the dispatched text` | Mock `navigator.clipboard.writeText`; dispatch `phx:copy` with `{text: "hello"}`. | Mock called once with `"hello"`. | TASK 3 — hook bound to wrong event name. |
| `Code-block copy delegated handler reads data-copy-text` | Render a `<button class="ui-code-block-copy" data-copy-text="snippet">Copy</button>`; dispatch `click`. | `navigator.clipboard.writeText` called once with `"snippet"`. | TASK 4 — handler reading inner text instead of the data attribute (loses escapes). |
| `PromptOnEvent ignores empty / whitespace input` | Stub `window.prompt` to return `""`, then `"   "`. | `pushEvent("rename_conversation", _)` is NOT called either time. | TASK 1 — accidentally renaming to empty / spaces. |

### E2E tests (Wallaby — `@moduletag :e2e`)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Positive — full sidebar flow | Open `/`; create a conv via "+ New"; send `"hello"`; create another conv via "+ New"; send `"second"`; click the first conv in the sidebar. | After click, the first conv's messages render; sidebar's active highlight moves; refresh preserves state. | TASK 1 — switching that breaks DB queries or DOM identity. |
| Positive — settings drawer round-trip | Open `/`; click ⚙; pick `gpt-4o-mini`; type a system prompt; set temperature 0.5; submit; close drawer; send `"hi"`; capture stub body. | Body uses the saved model + system prompt + temperature. | TASK 2 — drawer state lost on close. |
| Positive — code-block copy works in browser | Send a prompt that yields a fenced code block (stub returns the markdown directly); click the code block's "Copy" button. | Browser clipboard contains the un-escaped code text. | TASK 4 — escape leakage into the clipboard. |
| Negative — sidebar gracefully handles deleting the active conversation | Two convs; click ✕ on the active one; confirm. | Active id flips to the other conv; messages render; no client-side error. | TASK 1 — active conv deleted but state still references it → 500 on next event. |
| Negative — settings reject out-of-range temperature with a flash | Open settings; set temperature to `3.0` via dev-tools (bypassing the slider's `max`); submit. | Drawer stays open; flash error mentions `"temperature"`; no DB update. | TASK 2 — server-side validation missing. |
| Negative — token / cost header gracefully handles a missing usage block | Stub OpenAI to send `:stream_done` without a preceding `:stream_usage`. | Header still shows the prior cost (or `$0.00` for a new conv); no JS error; no Phoenix crash. | TASK 5 — UI assuming usage always arrives. |
| Negative — mid-stream transport drop triggers retry without duplicate prefix | Stub OpenAI to emit 5 tokens then drop; on retry serve the full 20 tokens. | The visible bubble does NOT contain the first 5 tokens twice; final text equals the second attempt's full output. | TASK 6 — append-style retry producing duplicated text. |

### Static / CI checks (no test framework)

| Check | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Migration `20260501000000_allow_multiple_conversations_per_session` exists and is idempotent | `mix ecto.migrate` then `mix ecto.migrate` again. | Second run prints `Already up`. | TASK 1 — non-idempotent unique-index drop. |
| `unique_index(:conversations, [:session_id])` is removed by the new migration | `rg "unique_index\\(:conversations" chat_app/priv/repo/migrations/` | The TASK 1 migration explicitly drops it; no leftover unique constraint elsewhere. | TASK 1 — second-conv insert fails with constraint error. |
| `usage_records` table created with FK ON DELETE CASCADE | `rg "on_delete: :delete_all" chat_app/priv/repo/migrations/*usage*` | At least two matches (conversation_id, message_id). | TASK 5 — orphaned rows after delete. |
| `floki` dependency available outside `:test` | `rg "{:floki," chat_app/mix.exs` | The `only: :test` modifier is removed. | TASK 4 — `Markdown.to_html/1` undefined in dev/prod. |
| `stream_options: %{include_usage: true}` present in the OpenAI body builder | `rg "include_usage" chat_app/lib/chat_app/openai.ex` | Exactly one match. | TASK 5 — feature shipped but API never asked for usage. |
| `@max_retries 2` and `@prices_per_1m_tokens` are module attributes (not magic numbers) | `rg "@max_retries|@prices_per_1m_tokens" chat_app/lib/chat_app/` | One match each. | TASKS 5+6 — drift / inconsistent values across call sites. |
| `mix compile --warnings-as-errors` clean after schema additions | Run after each task. | Exit 0; no unused-alias / unused-import warnings. | All tasks — leftover scaffolding from refactors. |
| `mix precommit` exits 0 with the new test files in place | Run after all tasks. | Exit 0; output includes `vitest` step (from Sprint 14). | All tasks — broken test wiring. |

---

## Tasks

### TASK 1 — Multi-conversation sidebar

**Context:**
Sprint 15 gives every browser session a single persistent conversation. F-3 expands that into a list of past conversations the user can switch between, the table-stakes "ChatGPT-like" UX. (Audit F-3, M.)

**Exact Scope:**

- `chat_app/lib/chat_app/conversations.ex`: add functions:
  ```elixir
  def list_conversations(session_id) when is_binary(session_id) do
    # For v1: all conversations are scoped by session_id; multi-user lands later.
    Conversation
    |> where(session_id: ^session_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def create_conversation(session_id, attrs \\ %{}) do
    %Conversation{session_id: session_id}
    |> Conversation.changeset(Map.merge(%{title: "New conversation"}, attrs))
    |> Repo.insert!()
  end

  def rename_conversation(id, title) when is_binary(title) do
    Repo.get!(Conversation, id)
    |> Conversation.changeset(%{title: title})
    |> Repo.update!()
  end

  def delete_conversation(id) do
    Repo.get!(Conversation, id) |> Repo.delete!()
  end

  def auto_title_from_first_message(content) when is_binary(content) do
    content |> String.slice(0, 60) |> String.trim() |> case do
      "" -> "New conversation"
      t  -> t
    end
  end
  ```

  Note: Sprint 15's `get_or_create/1` keyed conversations on `session_id`. With multiple conversations per session, `session_id` is no longer unique on `conversations`. Migration:

- `chat_app/priv/repo/migrations/20260501000000_allow_multiple_conversations_per_session.exs`:
  ```elixir
  defmodule ChatApp.Repo.Migrations.AllowMultipleConversationsPerSession do
    use Ecto.Migration

    def change do
      drop unique_index(:conversations, [:session_id])
      create index(:conversations, [:session_id])
    end
  end
  ```

  Update `Conversation.changeset/2` to remove `unique_constraint(:session_id)`.

- Update `Conversations.get_or_create/1` from Sprint 15: replace its semantics. Now it's `get_or_create_active/1` — find the most recent conversation for a session, or create one if none exist:
  ```elixir
  def get_or_create_active(session_id) do
    case list_conversations(session_id) do
      []           -> create_conversation(session_id)
      [latest | _] -> latest
    end
  end
  ```
  Replace all call sites in `chat_live.ex`.

- `chat_app/lib/chat_app_web/live/sidebar_component.ex` (new — Phoenix.Component, NOT a separate LiveView for v1):
  ```elixir
  defmodule ChatAppWeb.SidebarComponent do
    use Phoenix.Component
    import Phoenix.LiveView, only: []

    attr :conversations, :list, required: true
    attr :current_id, :integer, required: true

    def render(assigns) do
      ~H"""
      <aside class="ui-chat-sidebar flex h-full w-64 shrink-0 flex-col border-r border-foreground/10 bg-background/40">
        <div class="p-3">
          <button
            type="button"
            phx-click="new_conversation"
            class="w-full rounded-md border border-foreground/20 px-3 py-2 text-sm hover:bg-foreground/5"
          >+ New conversation</button>
        </div>

        <ul class="flex-1 overflow-y-auto p-2">
          <%= for conv <- @conversations do %>
            <li class="group flex items-center justify-between gap-2 rounded-md px-2 py-1.5 hover:bg-foreground/5"
                data-conversation-id={conv.id}>
              <button
                type="button"
                phx-click="switch_conversation"
                phx-value-id={conv.id}
                class={"flex-1 truncate text-left text-sm " <> if(conv.id == @current_id, do: "font-semibold", else: "text-foreground/70")}
              ><%= conv.title || "Untitled" %></button>

              <div class="opacity-0 group-hover:opacity-100 flex gap-1">
                <button type="button" phx-click="rename_conversation_prompt" phx-value-id={conv.id}
                  class="text-xs text-foreground/50 hover:text-foreground" aria-label="Rename">✎</button>
                <button type="button" phx-click="delete_conversation" phx-value-id={conv.id}
                  data-confirm="Delete this conversation?"
                  class="text-xs text-foreground/50 hover:text-red-500" aria-label="Delete">×</button>
              </div>
            </li>
          <% end %>
        </ul>
      </aside>
      """
    end
  end
  ```

- `chat_app/lib/chat_app_web/live/chat_live.ex`: add new event handlers:
  - `handle_event("switch_conversation", %{"id" => id}, socket)` — load messages, set `current_conversation_id`, redirect on partial JS reload.
  - `handle_event("new_conversation", _, socket)` — create a new conversation, switch to it.
  - `handle_event("rename_conversation_prompt", %{"id" => id}, socket)` — for v1 use `phx-hook` + browser `prompt()`; or simpler: dispatch a JS hook that calls `window.prompt()` and pushes back `rename_conversation` with the new title. Acceptable: skip the rename UI for v1 and only ship delete + switch + new. Decision: ship rename via `prompt()` to match audit's "hover-rename" requirement.
  - `handle_event("rename_conversation", %{"id" => id, "title" => title}, socket)` — DB update + reload list.
  - `handle_event("delete_conversation", %{"id" => id}, socket)` — DB delete; if it was the current conversation, switch to the next-most-recent or create a fresh one.

  In `mount/3`: load `conversations: list_conversations(session_id)`. After every mutating event, re-fetch the list and re-assign.

- `chat_app/assets/js/hooks/PromptOnEvent.js` (new): `phx-hook` that listens for a Phoenix server event and prompts the user for a string. Used by the rename flow:
  ```js
  const PromptOnEvent = {
    mounted() {
      this.handleEvent("prompt_rename", ({ id, current }) => {
        const next = window.prompt("Rename conversation:", current || "");
        if (next != null && next.trim() !== "") {
          this.pushEvent("rename_conversation", { id, title: next.trim() });
        }
      });
    }
  };
  ```
  Hook is attached to a hidden `<div phx-hook="PromptOnEvent" id="prompt-bridge" />` rendered once in the LiveView. The server's `rename_conversation_prompt` event pushes a `prompt_rename` JS event with the conversation's current title.

- Update `assets/js/app.js` to register `PromptOnEvent` in the `Hooks` map.

- Layout change: the existing `chat_live.ex` render currently wraps the chat in a single `<section>`. Restructure to:
  ```heex
  <div class="flex h-full">
    <ChatAppWeb.SidebarComponent.render conversations={@conversations} current_id={@current_conversation_id} />
    <section class="ui-chat-shell flex-1 ..."> ... existing chat ... </section>
  </div>
  ```

- Add `chat_app/assets/css/chat.css`: a `.ui-chat-sidebar` block with width transition and a media query that hides the sidebar below 768px (or sets `position: absolute` + a hamburger to open). For v1: hide below 768px and add a top-bar hamburger button. If the dev agent prefers an always-visible mobile sidebar, that is also acceptable.

- Auto-titling: in `handle_event("send_message", ...)`, when this is the FIRST user message in a conversation (verify by checking `Conversations.list_messages(conv_id)` is empty before the new insert), call `Conversations.rename_conversation(conv_id, Conversations.auto_title_from_first_message(text))`.

- Tests:
  - `chat_app/test/chat_app/conversations_test.exs`: extend with 5 new tests for `list_conversations/1`, `create_conversation/1`, `rename_conversation/2`, `delete_conversation/1`, `auto_title_from_first_message/1`.
  - `chat_app/test/chat_app_web/live/chat_live_sidebar_test.exs` (new): 6 tests:
    - `"sidebar lists all conversations for the session"`.
    - `"new_conversation creates a new conversation and switches to it"`.
    - `"switch_conversation loads its messages"`.
    - `"delete_conversation removes it from the list and switches to the next"`.
    - `"deleting the only conversation creates a fresh one"`.
    - `"first user message auto-titles the conversation"`.

**Acceptance Criteria:**
- [ ] Sidebar renders the list of conversations for the current session.
- [ ] "+ New conversation" creates a new conversation row and clears the chat.
- [ ] Clicking a conversation in the sidebar switches the active conversation and loads its messages.
- [ ] Hover-rename via `prompt()` updates the title in the DB and the sidebar.
- [ ] Delete with confirm removes the conversation; if it was active, the LiveView switches to the next-most-recent or creates a fresh one.
- [ ] First user message in a new conversation sets the title to the first 60 chars (trimmed).
- [ ] Below 768px the sidebar is hidden behind a hamburger toggle (or behaves acceptably if mobile is deferred — document the choice).
- [ ] All 5 new schema tests + 6 new LiveView tests pass.
- [ ] Migration `20260501000000_allow_multiple_conversations_per_session` runs cleanly forward and back.

**Edge Cases to Handle:**
- Sidebar empty after deleting the last conversation — auto-create a fresh one and switch to it.
- Rename to empty string — `prompt()` returns empty; the hook ignores it.
- Rename to a 1000-char title — truncate to 80 chars before persisting (add a `validate_length(:title, max: 80)` in the changeset).
- Two tabs of the same session_id — both share `list_conversations`; one tab's "new" doesn't appear in the other until reload. For v1, accept this; PubSub-based live update is a follow-up.
- Session reset (cookie cleared) — new session_id, empty sidebar; the orphaned conversations remain in the DB but are unreachable. For v1 accept; cleanup is a follow-up admin task.

**Do NOT do:**
- Do NOT introduce a separate LiveView for the sidebar — keep it as a Phoenix.Component.
- Do NOT add drag-to-reorder.
- Do NOT add search across conversations — separate feature.
- Do NOT add favorites / pinned conversations.
- Do NOT add multi-user accounts; session_id remains the scope key.

**Effort:** M
**Depends on:** Sprint 15 TASK 1 + TASK 2 (persistence schema and LiveView wiring). Migration update breaks `unique_index` from Sprint 15 — coordinate.

---

### TASK 2 — Settings drawer: model + system prompt + temperature

**Context:**
Sprint 11 made the OpenAI model configurable in `config/config.exs`, but the user has no UI to pick a model. The audit also flagged the absence of a system prompt as a "REQUIRES HUMAN INPUT" item; rather than commit a single hard-coded prompt, surface it as a per-conversation setting. (Audit F-4, M.)

**Exact Scope:**

- Schema: extend `ChatApp.Conversations.Conversation` with new fields:
  ```elixir
  field :model, :string
  field :system_prompt, :string
  field :temperature, :float
  ```
  Add to `Conversation.changeset/2` `cast` list and validate:
  - `:model` in a known list (`["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]` — verify against current OpenAI offerings at sprint start; pin the list as a module attribute).
  - `:temperature` between 0.0 and 2.0 (`validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)`).
  - `:system_prompt` length ≤ 4000 chars.

- Migration `20260508000000_add_settings_to_conversations.exs`:
  ```elixir
  alter table(:conversations) do
    add :model, :string
    add :system_prompt, :text
    add :temperature, :float
  end
  ```

- `chat_app/lib/chat_app/conversations.ex`: add `update_conversation_settings/2`:
  ```elixir
  def update_conversation_settings(id, attrs) do
    Repo.get!(Conversation, id)
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end
  ```

- `chat_app/lib/chat_app/openai.ex`: change the `body` construction to accept overrides:
  ```elixir
  def stream(messages, lv_pid, opts \\ []) do
    model = Keyword.get(opts, :model) || Application.get_env(:chat_app, :openai_model, "gpt-4o")
    system_prompt = Keyword.get(opts, :system_prompt)
    temperature = Keyword.get(opts, :temperature)

    msgs =
      case system_prompt do
        nil -> messages
        ""  -> messages
        sp  -> [%{role: :system, content: sp} | messages]
      end

    body =
      %{model: model, messages: Enum.map(msgs, &%{role: &1.role, content: &1.content}), stream: true}
      |> maybe_put(:temperature, temperature)
    ...
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v),    do: Map.put(map, k, v)
  ```

- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - In `handle_event("send_message", ...)`, fetch the active conversation's settings and pass to `openai_module().stream/3`:
    ```elixir
    conv = Conversations.get_conversation!(socket.assigns.current_conversation_id)
    opts = [model: conv.model, system_prompt: conv.system_prompt, temperature: conv.temperature]
    Task.Supervisor.start_child(ChatApp.TaskSupervisor, fn ->
      openai_module().stream(messages, pid, opts)
    end)
    ```
  - Add `handle_event("toggle_settings", _, socket)` — flip `assigns.settings_open` boolean.
  - Add `handle_event("save_settings", %{"settings" => params}, socket)` — call `update_conversation_settings/2`; reload `conv` and toast "Settings saved".

  - Render a settings drawer overlay when `@settings_open`:
    ```heex
    <%= if @settings_open do %>
      <div class="fixed inset-0 z-40 bg-black/40" phx-click="toggle_settings"></div>
      <aside class="fixed right-0 top-0 z-50 h-full w-96 overflow-y-auto bg-background p-6 shadow-2xl">
        <h2 class="text-lg font-semibold">Conversation settings</h2>
        <.form for={%{}} as={:settings} phx-submit="save_settings" class="mt-4 space-y-4">
          <label class="block text-sm">
            Model
            <select name="settings[model]" class="mt-1 w-full rounded-md border border-foreground/20 bg-background p-2">
              <%= for m <- @model_options do %>
                <option value={m} selected={m == @current_conversation.model}><%= m %></option>
              <% end %>
            </select>
          </label>
          <label class="block text-sm">
            System prompt
            <textarea name="settings[system_prompt]" rows="6" class="mt-1 w-full ..."><%= @current_conversation.system_prompt %></textarea>
          </label>
          <label class="block text-sm">
            Temperature: <span><%= @current_conversation.temperature || 1.0 %></span>
            <input type="range" name="settings[temperature]" min="0" max="2" step="0.1"
                   value={@current_conversation.temperature || 1.0} class="mt-1 w-full" />
          </label>
          <button type="submit" class="rounded-md bg-foreground/10 px-4 py-2 text-sm">Save</button>
        </.form>
      </aside>
    <% end %>
    ```
  - Add a "⚙ Settings" button in the header rail (next to the theme toggle).

  - Compute `@model_options` at compile time as a module attribute or in `mount/3`:
    ```elixir
    @model_options ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]
    ```

- Tests:
  - `chat_app/test/chat_app/conversations_test.exs`: 4 new tests on `update_conversation_settings/2` covering each field + a validation failure.
  - `chat_app/test/chat_app/openai_test.exs`: 2 new tests asserting that `system_prompt` and `temperature` end up in the request body.
  - `chat_app/test/chat_app_web/live/chat_live_settings_test.exs` (new): 3 tests:
    - `"toggle_settings opens and closes the drawer"`.
    - `"save_settings persists model + system_prompt + temperature"`.
    - `"send_message uses the saved settings"` — by stubbing the OpenAI stream with `Req.Test` and asserting the body.

**Acceptance Criteria:**
- [ ] Conversation rows have nullable `model`, `system_prompt`, `temperature` columns.
- [ ] Migration runs cleanly forward and back.
- [ ] Settings drawer opens from the header rail.
- [ ] Selecting a model + entering a system prompt + setting temperature persists to the conversation.
- [ ] The next `send_message` includes the system prompt as `role: "system"` first message and the temperature in the request body.
- [ ] Validation rejects out-of-range temperature, invalid model, oversize system prompt.
- [ ] All 9 new tests pass.

**Edge Cases to Handle:**
- Settings empty (newly-created conversation) — the OpenAI body falls back to the global `:openai_model` config and omits `temperature` and `system_prompt`.
- User changes the model mid-conversation — the next message uses the new model; prior messages don't replay.
- System prompt with leading/trailing whitespace — trim before persisting.
- Two tabs save settings simultaneously — last write wins; no PubSub for v1.

**Do NOT do:**
- Do NOT add `top_p`, `presence_penalty`, `frequency_penalty`, `max_tokens` controls — out of scope; add as a follow-up.
- Do NOT add a "Reset to defaults" button (acceptable but defer).
- Do NOT support per-message overrides.
- Do NOT add streaming preview of how the system prompt affects responses.

**Effort:** M
**Depends on:** Sprint 11 TASK 4 (configurable model), Sprint 15 TASK 1 (persistence). The 2026-04-24 model list above must be re-verified at sprint start; the dev agent should call `mix hex.info` on `req` and then check OpenAI's current model menu via `https://platform.openai.com/docs/models` and update the module attribute if needed.

---

### TASK 3 — Copy + feedback controls on assistant bubbles

**Context:**
Cheap polish, high perceived value. After persistence (Sprint 15), feedback events have a place to land (a `feedback` table). For v1 emit telemetry only — no DB. (Audit F-6, S.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/live/chat_live.ex` — inside the assistant `message_bubble` component (or its render function), append a hover-revealed action row:
  ```heex
  <div class="ui-chat-message-actions mt-2 flex gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
    <button type="button"
      phx-click={JS.dispatch("phx:copy", detail: %{text: @message.content})}
      class="text-xs text-foreground/50 hover:text-foreground" aria-label="Copy">⎘ Copy</button>
    <button type="button"
      phx-click="feedback" phx-value-message-index={@index} phx-value-rating="up"
      class="text-xs text-foreground/50 hover:text-foreground" aria-label="Thumbs up">▲</button>
    <button type="button"
      phx-click="feedback" phx-value-message-index={@index} phx-value-rating="down"
      class="text-xs text-foreground/50 hover:text-foreground" aria-label="Thumbs down">▼</button>
  </div>
  ```
  Wrap the bubble in `class="group relative"` so `group-hover` works.

- Add a JS hook for clipboard. There is no built-in `phx:copy`. Add `chat_app/assets/js/hooks/Clipboard.js`:
  ```js
  window.addEventListener("phx:copy", (e) => {
    navigator.clipboard.writeText(e.detail.text);
  });
  ```
  Import once in `assets/js/app.js`.

- `chat_app/lib/chat_app_web/live/chat_live.ex`: add `handle_event("feedback", %{"message-index" => idx, "rating" => rating}, socket)`:
  ```elixir
  :telemetry.execute(
    [:chat_app, :feedback],
    %{count: 1},
    %{
      conversation_id: socket.assigns.current_conversation_id,
      message_index: String.to_integer(idx),
      rating: rating
    }
  )
  socket = put_flash(socket, :info, "Thanks for the feedback.")
  {:noreply, socket}
  ```

- Tests:
  - `chat_app/test/chat_app_web/live/chat_live_feedback_test.exs` (new): 2 tests:
    - `"feedback event emits a telemetry event with the rating"` — attach `:telemetry.attach`, click button, assert handler ran with correct metadata.
    - `"feedback event sets a flash"`.
  - `chat_app/assets/test/hooks/Clipboard.test.js` (new): mock `navigator.clipboard.writeText`; dispatch `phx:copy` event with `{ text: "hello" }`; assert mock called with `"hello"`.

**Acceptance Criteria:**
- [ ] Assistant bubbles show ⎘ Copy / ▲ / ▼ on hover.
- [ ] Clicking Copy writes the assistant message text to the clipboard.
- [ ] Clicking ▲ or ▼ emits `[:chat_app, :feedback]` telemetry with `:rating` metadata.
- [ ] No persistence of feedback in v1.
- [ ] All 2 + 1 new tests pass.

**Edge Cases to Handle:**
- Browser without clipboard API (very old) — `navigator.clipboard` is undefined; fall back to `document.execCommand("copy")` via a temporary textarea. For v1 acceptable to skip the fallback; modern browsers all support it.
- Copying mid-stream (during `is_sending`) — copies whatever is currently in `@message.content`. Acceptable.
- Repeated thumbs clicks — each emits a telemetry event; v1 does not deduplicate.

**Do NOT do:**
- Do NOT persist feedback in this task. Add in a follow-up.
- Do NOT add a "Copy as Markdown" button (audit lists it; defer).
- Do NOT add inline edit / regenerate-from-this-message — separate feature.

**Effort:** S
**Depends on:** Sprint 15 TASK 1 (conversation_id available in assigns).

---

### TASK 4 — Markdown code-block polish: copy button + language pill

**Context:**
Code snippets are a heavy use case in chat. Sprint 11 TASK 2 enabled `escape: true`, which preserves fenced-code semantics. The existing render path uses Earmark's default `<pre><code class="elixir">` output. (Audit F-9, M.)

**Exact Scope:**

- `chat_app/lib/chat_app/markdown.ex`: extend `to_html/1` to post-process the Earmark output. Add a `Floki.parse_fragment/1` step that finds each `<pre><code class="...">` and wraps it in a `<div class="ui-code-block">` with a header bar:
  ```elixir
  def to_html(markdown) do
    {:ok, raw_html, _msgs} = Earmark.as_html(markdown, escape: true)
    raw_html |> wrap_code_blocks()
  end

  defp wrap_code_blocks(html) do
    case Floki.parse_fragment(html) do
      {:ok, frag} ->
        frag
        |> Floki.traverse_and_update(&maybe_wrap_pre/1)
        |> Floki.raw_html()

      {:error, _} ->
        html
    end
  end

  defp maybe_wrap_pre({"pre", attrs, [{"code", code_attrs, children}]}) do
    lang =
      Enum.find_value(code_attrs, fn
        {"class", c} -> List.first(String.split(c, " ", trim: true))
        _ -> nil
      end) || "text"

    code_text =
      children
      |> Enum.map_join("", fn
        s when is_binary(s) -> s
        _ -> ""
      end)
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    {"div", [{"class", "ui-code-block"}, {"data-language", lang}],
     [
       {"div", [{"class", "ui-code-block-header"}],
        [
          {"span", [{"class", "ui-code-block-lang"}], [lang]},
          {"button", [
             {"type", "button"},
             {"class", "ui-code-block-copy"},
             {"data-copy-text", code_text}
           ], ["Copy"]}
        ]},
       {"pre", attrs, [{"code", code_attrs, children}]}
     ]}
  end

  defp maybe_wrap_pre(other), do: other
  ```

- `chat_app/assets/js/app.js`: add a delegated click handler:
  ```js
  document.addEventListener("click", (e) => {
    const btn = e.target.closest(".ui-code-block-copy");
    if (!btn) return;
    const text = btn.getAttribute("data-copy-text");
    if (text) navigator.clipboard.writeText(text);
  });
  ```

- `chat_app/assets/css/chat.css`: add styling for `.ui-code-block`, `.ui-code-block-header`, `.ui-code-block-lang`, `.ui-code-block-copy`. Header bar visually distinct from the code body; uppercase language pill in a muted accent.

- Verify `floki` is in `mix.exs` (it is, as a test dep). Move it to a non-test dep — change `{:floki, ...}` from `only: :test` to no scope:
  ```elixir
  {:floki, ">= 0.30.0"}
  ```

- Tests:
  - `chat_app/test/chat_app/markdown_test.exs`: add 4 tests:
    - `"to_html wraps a fenced elixir block in .ui-code-block with data-language=elixir"`.
    - `"to_html with an unlabeled fence sets data-language=text"`.
    - `"to_html does NOT wrap inline code (single backtick)"`.
    - `"to_html with multiple code blocks wraps each independently"`.
  - Update the existing XSS / escape tests to be tolerant of the new wrapper structure (they test that `<script>` is escaped — wrapping doesn't undo escape).

**Acceptance Criteria:**
- [ ] Each fenced code block in assistant output renders inside `<div class="ui-code-block" data-language="...">` with a header bar.
- [ ] The header shows the language (or "text" if absent).
- [ ] Clicking the Copy button writes the un-escaped code to the clipboard.
- [ ] XSS protection from Sprint 11 TASK 2 is preserved — script tags inside code fences remain HTML-escaped in the rendered output.
- [ ] Inline code (single backtick) is NOT wrapped (renders as `<code>` only).
- [ ] All 4 new tests pass.
- [ ] `floki` is available in all envs.

**Edge Cases to Handle:**
- A nested fenced block (Earmark doesn't support; out of scope).
- A fence with a multi-class language (e.g. `class="elixir highlight-source"`) — take the first token.
- A code block containing the literal substring `</textarea>` — already escaped by Earmark; the `data-copy-text` attribute is double-quote-safe (Floki `raw_html/1` handles attribute escaping).
- A 1MB code block — `data-copy-text` attribute carries it; modern browsers handle multi-MB attributes fine. Acceptable.

**Do NOT do:**
- Do NOT add syntax highlighting (Makeup Elixir / Prism / highlight.js) in this task. Add as a follow-up.
- Do NOT add line numbers.
- Do NOT add a "Run code" button (way out of scope).

**Effort:** M
**Depends on:** Sprint 11 TASK 2 (escape: true).

---

### TASK 5 — Token / cost accounting per conversation

**Context:**
OpenAI's streaming responses include a final `usage` block when the request body sets `stream_options: { include_usage: true }`. Persisting this lets the operator surface "this conversation cost $X.XX" and "your IP has spent $Y today." (Audit F-8, M.)

**Exact Scope:**

- Schema: add a new table `usage_records`:
  ```elixir
  create table(:usage_records) do
    add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
    add :message_id, references(:messages, on_delete: :delete_all)
    add :model, :string, null: false
    add :prompt_tokens, :integer, null: false
    add :completion_tokens, :integer, null: false
    add :total_tokens, :integer, null: false
    add :estimated_cost_cents, :integer, null: false
    timestamps(type: :utc_datetime)
  end

  create index(:usage_records, [:conversation_id])
  ```
  Migration `20260515000000_create_usage_records.exs`.

- `chat_app/lib/chat_app/conversations/usage_record.ex` (new): standard Ecto schema mirroring the table.

- `chat_app/lib/chat_app/conversations.ex`:
  - `record_usage(conversation_id, message_id, model, usage_map)` — converts OpenAI's usage map (`%{"prompt_tokens" => p, "completion_tokens" => c, "total_tokens" => t}`) into a record with an estimated cost. Cost lookup table:
    ```elixir
    @prices_per_1m_tokens %{
      "gpt-4o"        => %{input: 2_50,  output: 10_00},
      "gpt-4o-mini"   => %{input: 15,    output: 60},
      "gpt-4.1"       => %{input: 2_00,  output: 8_00},
      "gpt-4.1-mini"  => %{input: 40,    output: 1_60}
    }
    ```
    (Verify these against OpenAI's pricing page at sprint start. Prices are in cents per 1M tokens.) Compute `estimated_cost_cents = round((p * input_price + c * output_price) / 1_000_000)`.
  - `usage_for_conversation/1` and `usage_for_session/1` — sum totals.

- `chat_app/lib/chat_app/openai.ex`:
  - Add `stream_options: %{include_usage: true}` to the request body.
  - `parse_sse_chunk/3` already passes events to the LiveView pid. Extend to recognize the usage block:
    - The final SSE event before `[DONE]` has the shape `data: {"choices":[{...}], "usage": {...}}`. Pass it to the LiveView as `{:stream_usage, usage_map}` (a new event).
  - In `chat_app/lib/chat_app/openai/sse.ex`: extend the parser to extract `usage` if present and emit `{:stream_usage, ...}`.

- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Add `handle_info({:stream_usage, usage}, socket)`:
    ```elixir
    if assistant_id = socket.assigns.assistant_message_id do
      Conversations.record_usage(
        socket.assigns.current_conversation_id,
        assistant_id,
        @current_model_for_request, # store the resolved model in assigns when send_message fires
        usage
      )
    end
    {:noreply, socket}
    ```
  - In `mount/3`, also load `usage_total_cents = Conversations.usage_for_conversation(conv.id)` and assign it.
  - Render in the header rail (next to the conversation title): "$0.07" or similar. Format helper: `cents_to_dollars(cents) :: "$X.XX"`.

- Update the stubs in `lib/chat_app/openai/stub.ex` and `lib/chat_app/openai/e2e_stub.ex` to optionally send a `{:stream_usage, %{"prompt_tokens" => ..., "completion_tokens" => ..., "total_tokens" => ...}}` before `:stream_done`. Make the stub send a fake usage block when configured to (gated by `Application.get_env(:chat_app, :stub_usage_response, ...)`).

- Tests:
  - `chat_app/test/chat_app/conversations_test.exs`: 5 tests:
    - `"record_usage stores the row with the right cost"`.
    - `"record_usage rejects non-positive token counts"`.
    - `"usage_for_conversation sums all records"`.
    - `"unknown model defaults to a documented fallback price (or zero, with a Logger warning)"`.
    - `"deleting a conversation cascades to usage_records"`.
  - `chat_app/test/chat_app/openai_test.exs`: 2 tests:
    - `"stream emits :stream_usage when the usage block arrives"`.
    - `"stream still works correctly when the usage block is missing"`.

**Acceptance Criteria:**
- [ ] `usage_records` table exists with the documented columns.
- [ ] OpenAI request body includes `stream_options: {"include_usage": true}`.
- [ ] When the API returns a usage block, a `usage_records` row is inserted.
- [ ] The header displays the conversation's current cost.
- [ ] All 7 new tests pass.
- [ ] Migration up + down work cleanly.

**Edge Cases to Handle:**
- API returns no usage (older models, errors) — no insert; cost stays at the prior value.
- Cost computation rounds to nearest cent; very-cheap conversations may show "$0.00" — acceptable.
- Unknown model price: log a warning and store cost as 0. Document.
- `record_usage` called with a stale message_id (deleted by Regenerate): handle the FK violation gracefully — wrap in `try/rescue Ecto.ConstraintError` and skip.

**Do NOT do:**
- Do NOT compute per-IP daily caps in this task — tied to F-2's IP-keyed plug, deferred.
- Do NOT add a billing dashboard.
- Do NOT add notifications when cost exceeds a threshold.
- Do NOT add a CSV export.

**Effort:** M
**Depends on:** Sprint 15 TASK 1 (conversations + messages), Sprint 11 TASK 4 (configurable model).

---

### TASK 6 — Bounded retry semantics for transport-level failures

**Context:**
OpenAI streaming connections occasionally drop mid-stream. Today the LiveView surfaces `:stream_error` and the partial assistant message stays as-is. A bounded retry on transport-level failures only (NOT 4xx authorization or 429 rate limit) recovers most flakes invisibly. (Audit F-10, M.)

**Exact Scope:**

- `chat_app/lib/chat_app/openai.ex`: add an internal retry loop:
  ```elixir
  @max_retries 2

  def stream(messages, lv_pid, opts \\ []) do
    do_stream(messages, lv_pid, opts, 0)
  end

  defp do_stream(messages, lv_pid, opts, attempt) do
    case attempt_stream(messages, lv_pid, opts) do
      :ok ->
        :ok

      {:retryable, reason} when attempt < @max_retries ->
        Logger.warning("OpenAI retryable failure",
          attempt: attempt + 1, reason: inspect(reason), message_count: length(messages))
        Process.sleep(backoff_ms(attempt))
        do_stream(messages, lv_pid, opts, attempt + 1)

      {:fatal, reason} ->
        send(lv_pid, {:stream_error, format_reason(reason)})
        :error
    end
  end

  defp backoff_ms(attempt), do: trunc(:math.pow(2, attempt) * 250) # 250ms, 500ms, 1000ms

  defp attempt_stream(messages, lv_pid, opts) do
    # ... existing streaming code, but instead of send(lv_pid, {:stream_error, ...}),
    # return one of:
    #   :ok (on :stream_done sent successfully)
    #   {:retryable, reason} for transport errors and 5xx
    #   {:fatal, reason} for 4xx and exceptions
  end
  ```
  - **Retryable**: `{:error, %Mint.TransportError{}}`, `{:error, %Req.TransportError{}}`, `{:error, :timeout}`, `{:error, :closed}`, status `5xx`.
  - **Fatal**: status `4xx`, any exception inside the rescue block, status `200` followed by `:stream_done` (success path returns `:ok` instead).

- Critical: retries must NOT replay tokens to the LiveView that were already sent on a prior attempt. Solution for v1: on a retryable failure, the LiveView would have received partial `:stream_token` events. Send a `{:stream_retrying, attempt}` event so the LiveView can decide. Two acceptable strategies:
  1. **Discard partial output**: on `:stream_retrying`, the LiveView clears `assigns.stream_buffer` and removes the partial assistant message from `messages` and DB. The retry starts fresh.
  2. **Append**: leave the partial message; retry continues streaming and the new tokens append.

  Choose strategy 1 for v1 — cleaner UX, no "duplicate prefix" artifacts. The LiveView resets the assistant message; the user sees a brief blank then the full reply.

- `chat_app/lib/chat_app_web/live/chat_live.ex`: add `handle_info({:stream_retrying, attempt}, socket)`:
  ```elixir
  if assistant_id = socket.assigns.assistant_message_id do
    Conversations.delete_message(assistant_id)
  end

  {:noreply,
   assign(socket,
     stream_buffer: "",
     assistant_message_id: nil,
     messages: drop_last_assistant(socket.assigns.messages),
     errors: socket.assigns.errors ++ [%{for_index: -1, reason: "Reconnecting (attempt #{attempt + 1}/2)..."}]
   )}
  ```
  Add helper `defp drop_last_assistant(messages) do ... end`.

- Tests (`chat_app/test/chat_app/openai_retry_test.exs`, new):
  - `"transport error retries up to 2 times"` — Bypass returns connection-reset twice then succeeds; assert final `:stream_done`.
  - `"3rd transport error escalates to :stream_error"`.
  - `"4xx response does NOT retry"` — Bypass returns 401; assert immediate `:stream_error`, no retry log entry.
  - `"5xx response retries"` — Bypass returns 500 once, then 200; assert success.
  - `":stream_retrying is sent before each retry attempt"`.
  - `"backoff_ms increases between retries"` — pure unit test on the helper.

- `chat_app/test/chat_app_web/live/chat_live_retry_test.exs` (new):
  - `":stream_retrying clears the partial assistant message"`.
  - `":stream_retrying inserts a transient error message"`.

**Acceptance Criteria:**
- [ ] `OpenAI.stream/3` retries transport-level failures up to 2 times with exponential backoff (250ms, 500ms, 1000ms).
- [ ] 4xx responses do NOT retry; `:stream_error` is sent immediately.
- [ ] 5xx responses retry.
- [ ] On retry, the LiveView clears the partial assistant message and DB row.
- [ ] After exhausting retries, the LiveView falls back to the existing error UX from Sprint 12 TASK 2.
- [ ] Logger entries are emitted for each retry attempt.
- [ ] All 6 + 2 new tests pass.
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- Retry triggers while user has already sent the next message (rare; the rate limit and `is_sending` guard prevent it). For absolute correctness, `:stream_retrying` checks `socket.assigns.is_sending` before mutating.
- Retry triggers AFTER user clicks Stop — the retry loop checks for a process-cancellation flag. For v1 simplicity: the retry loop continues; the LiveView's `terminate/2` from Sprint 12 TASK 1 kills the supervised task on disconnect, breaking the retry. Acceptable.
- Backoff exceeds the LiveView's tolerance for a frozen UI — 250+500+1000 = 1.75s max blocking before fatal. Acceptable.
- DB row already deleted by a parallel Stop event — `delete_message/1` raises; wrap in `try`. The existing `Conversations.delete_message/1` from Sprint 15 TASK 4 raises on missing — adjust to use `Repo.delete/1` with the unwrapped result, returning `{:ok, _} | {:error, _}`.

**Do NOT do:**
- Do NOT retry on 429 (rate limit) — the user must back off; surface immediately.
- Do NOT retry on 401/403 — credential issues.
- Do NOT exceed 2 retries for v1.
- Do NOT add jitter — fixed exponential backoff is sufficient.
- Do NOT add per-conversation retry policy.

**Effort:** M
**Depends on:** Sprint 13 TASK 4 (Logger), Sprint 12 TASK 1 (TaskSupervisor), Sprint 15 TASK 2 (DB-backed assistant_message_id).

---

## DEFERRED (to a future Sprint 17+)

After this sprint, the audit's backlog is fully addressed. Items NOT covered anywhere in Sprints 11-16 (and therefore deferred to a future planning round) include:

- **Per-IP / per-user rate caps** at the plug layer (F-2 option B / multi-user accounts).
- **PubSub-based live sidebar updates** across tabs.
- **Drag-to-reorder, search, favorites** on the conversation sidebar.
- **Full-text search** over message contents (FTS5).
- **Admin dashboard** for cost / usage analytics.
- **Postgres migration** path from SQLite.
- **Containerized E2E (Wallaby + Chrome) in CI**.
- **Syntax highlighting** in code blocks (Makeup Elixir / Prism).
- **Mobile-optimized** sidebar / bubble interactions.
- **Audio / image inputs** (multimodal).
- **Streaming preview** for system-prompt edits.

## SPRINT RISKS

- **Migration coordination risk** (TASK 1): the unique-index drop is non-trivial in production; verify the migration is idempotent and re-runnable.
- **OpenAI pricing drift** (TASK 5): the price table is hardcoded. The dev agent must verify prices at sprint start. Long-term fix: pull prices from a config file or env.
- **Retry strategy choice** (TASK 6): "discard partial output" may surprise users on a long generation. Acceptable for v1; revisit if user complaints arise.
- **`Floki.traverse_and_update/2` performance** (TASK 4): for very large messages with many code blocks, this is O(N) per render. Acceptable; benchmark if it becomes hot.
- **System-prompt validation length cap** (TASK 2) **may be too low for some users**: 4000 chars is sufficient for most use cases. Configurable later.
- **Telemetry-only feedback** (TASK 3) **is observable nowhere**: until Sprint 17+ adds a feedback table, ▲/▼ clicks are visible only in logs. Document.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:
- [ ] All six tasks pass their acceptance criteria.
- [ ] `mix precommit` exits 0.
- [ ] `cd assets && npm test` exits 0.
- [ ] `mix test --exclude real_api` exits 0.
- [ ] CI is green on a final PR.
- [ ] The product surface includes: sidebar with switching, settings drawer with model/system prompt/temperature, hover controls on assistant bubbles (copy + thumbs), code-block headers with copy buttons, header-rail cost display, transparent retry on transport flakes.
- [ ] `README.md` documents the new env vars (none new at OS level — settings live in the DB).
- [ ] `CHANGELOG.md` `[Unreleased]` documents this sprint's `### Added`, `### Changed`.
- [ ] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict
TBD

## Completion Notes
TBD
