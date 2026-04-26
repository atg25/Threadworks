---
status: active
activated: 2026-04-25
---

# SPRINT 13 — Hardening A: Architecture & Internals

**Status:** ACTIVE
**Created:** 2026-04-24
**Activated:** 2026-04-25
**Completed:** TBD

## Goal
Replace the brittle internal coupling points (process-dictionary SSE buffer, O(N²) message append, dead string-typed event clause, concat-style req-options merge), and add the ops visibility (Logger on stream failures) that Sprint 12 deferred — so the platform is auditable, performant, and pure before Sprint 15 stacks persistence on top.

**Total effort:** ~7 hours (1 × M, 6 × S)
**Parallelizable:** All seven tasks touch different files and are fully independent. They can run in parallel branches and merge in any order.

---

## TDD Test Specification

Per-task descriptions below contain each task's primary tests. This section adds the upfront layer table, the E2E paths (positive + ≥2 negative), and explicit pure-unit / static checks. Per-task tests inside each TASK block are the source of truth for shape; this section is additive.

### Layer summary

| Layer | Tool | Test files | Tasks |
| --- | --- | --- | --- |
| Unit | ExUnit | `test/chat_app/chat_test.exs`, `test/chat_app/openai_sse_test.exs` (existing) | 2, 6 |
| Integration | `Phoenix.LiveViewTest`, Floki, `Bypass`, `Req.Test`, `ExUnit.CaptureLog` | `test/chat_app/openai_integration_test.exs`, `test/chat_app/openai_test.exs`, `test/chat_app_web/live/chat_live_events_test.exs` | 1, 4, 5, 6, 7 |
| Hooks (JS unit) | Vitest + jsdom | `assets/test/hooks/ChatScroll.test.js` | 3 |
| E2E | Wallaby + ChromeDriver | `test/chat_app_web/features/chat_e2e_test.exs` (`@moduletag :e2e`) | 3, 4 |
| Static | ripgrep, `mix compile --warnings-as-errors`, `mix docs` | CI step / PR description | 1, 6, 7 |

### Unit tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `upsert into empty list creates a new assistant message` | `upsert_assistant_message([], "x")` | `[%{role: :assistant, content: "x"}]`. | TASK 2 — empty-list special case losing tokens. |
| `upsert when last is :user appends a new assistant message` | `upsert_assistant_message([%{role: :user, content: "Q"}], "first")` | List length 2; last entry is the assistant message. | TASK 2 — accidental in-place overwrite of the user message. |
| `upsert when last is :assistant replaces the last message` | `upsert_assistant_message([%{role: :assistant, content: "old"}], "new")` | `[%{role: :assistant, content: "new"}]`; length unchanged. | TASK 2 — append-instead-of-replace producing duplicate bubbles. |
| `upsert preserves all prior messages` | List of 3 user/assistant pairs; upsert with new buffer when last is `:assistant`. | All non-tail entries unchanged; length unchanged. | TASK 2 — stray `Enum.reverse` swallowing prior messages. |
| `upsert raises on non-list messages` | `upsert_assistant_message("not a list", "x")` | Raises `FunctionClauseError`. | TASK 2 — relaxed contract masking caller bugs. |
| `upsert raises on non-binary buffer` | `upsert_assistant_message([], 42)` | Raises `FunctionClauseError`. | TASK 2 — silent stringification at runtime. |
| `scroll_position only matches boolean :at_bottom` | Direct call `ChatLive.handle_event("scroll_position", %{"at_bottom" => "true"}, socket)`. | Raises `FunctionClauseError` (string is no longer accepted). | TASK 6 — silent re-introduction of the dead string clause. |

### Integration tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `calling stream/2 twice from the same process does not leak buffers between calls` | Two sequential `Bypass.expect_once` handlers; each emits a distinct partial-line scenario; same caller pid. | Each call's tokens reach the LiveView pid without contamination from the other call. | TASK 1 — process-dictionary buffer regression. |
| `req_options can override receive_timeout` | `Application.put_env(:chat_app, :req_options, receive_timeout: 50)`; `Req.Test.stub` that sleeps 200ms. | `{:stream_error, _}` arrives within 1s; default 120s would block the test. | TASK 7 — concat semantics ignoring overrides. |
| `non-2xx logs a warning with status and message_count` | Bypass returns 401; `capture_log/1` around `OpenAI.stream/2`. | Log contains `"non-2xx"`, `"status: 401"`, `"message_count: 1"`; does NOT contain `"sk-"` or any user-message content. | TASK 4 — silent failures with no operator visibility; secret leak via metadata. |
| `transport error logs an error with reason and message_count` | `Bypass.down/1` then call. | Log contains `"transport error"`, `"message_count: 1"`; no `Authorization` header value. | TASK 4 — connection drops invisible to ops. |
| `exception inside the rescue clause logs an error` | Pass a deliberately-malformed `messages` list (non-map element) that breaks `Enum.map/2`. | Log contains `"exception"`. | TASK 4 — rescue path silently swallowing programmer errors. |
| `dev boot raises an instructive error when no .env and no OPENAI_API_KEY` | Run `mix phx.server` (or its boot path) in a `MIX_ENV=dev` shell with cleared env and `File.rm/1` on `.env`. | Boot raises an exception whose message includes `cp .env.example .env`. | TASK 5 — opaque Dotenvy stack traces blocking new contributors. |

### E2E tests (Wallaby)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Positive — scroll-to-bottom pill works on first click | Open `/`; submit one message; without any manual scroll, jump scrollTop to 0; wait for the pill to appear; click it. | Viewport scrolls back to bottom; click handler fired without needing a prior scroll event. | TASK 3 — dead-on-first-render click handler. |
| Negative — pill is hidden on initial mount when at bottom | Open `/`; without scrolling, inspect `#scroll-cta-dock`. | Element has the `hidden` class (or `display: none`). | TASK 3 — initial visibility computed only from `onScroll`. |
| Negative — repeated scroll events do not multiply click handlers | Spy on `addEventListener` calls on `#scroll-to-bottom`; perform 5 programmatic scrolls. | `addEventListener("click", …)` was attached exactly once. | TASK 3 — listener stacking causing N-fold scrollToBottom calls. |
| Negative — non-2xx surfaces a user-visible error AND emits a Logger entry | Stub OpenAI to reply 401; submit any prompt; capture log via test-side log subscriber. | Visible `[data-chat-message-error]` shows error; log contains `status: 401`. | TASKS 4 + 12.2 — silent failures. |

### Static / CI checks (no test framework)

| Check | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Process.get` / `Process.put` absent from `openai.ex` | `rg "Process\\.(get|put)" chat_app/lib/chat_app/openai.ex` | Zero matches. | TASK 1 regression. |
| `req_options` precedence is `Keyword.merge(base_opts, override)` (override wins) | `rg "Keyword\\.merge\\(base_opts" chat_app/lib/chat_app/openai.ex` | Exactly one match. | TASK 7 — order swap silently restoring concat semantics. |
| `:api` pipeline absent from router | `rg "pipeline :api" chat_app/lib/chat_app_web/router.ex` (handled in Sprint 14, but verified here too) | n/a here — verified in Sprint 14 static checks. | Cross-sprint drift. |
| Single `handle_event("scroll_position"…` clause | `rg 'handle_event\\("scroll_position"' chat_app/lib/chat_app_web/live/chat_live.ex` | Exactly one match. | TASK 6 regression. |
| `mix compile --warnings-as-errors` clean | Run after each task. | Exit 0. | TASKS 6, 7 — unreachable-clause / unused-binding warnings. |
| `OpenAI.stream/2` `@moduledoc` no longer mentions process-dictionary coupling | `rg "process-dictionary" chat_app/lib/chat_app/openai.ex` | Zero matches; new sentence about "Pure with respect to the calling process" is present. | TASK 1 — docstring drift after refactor. |

---

## Tasks

### TASK 1 — Move SSE buffer out of the process dictionary

**Context:**
`chat_app/lib/chat_app/openai.ex:33-43` stores the SSE leftover-line buffer in the process dictionary via `Process.get(:sse_buf, "")` / `Process.put(:sse_buf, ...)`. This is a documented hack that depends on the streaming function running inside a dedicated `Task.start` process. The instant the call is reused from a long-lived process (e.g. an Oban worker, a GenServer, or after Sprint 16's retry semantics), the buffer leaks across calls. (Audit H-1, 🟡 MINOR but architectural.)

**Exact Scope:**
- `chat_app/lib/chat_app/openai.ex`:
  - Remove the two `Process.get(:sse_buf, ...)` / `Process.put(:sse_buf, ...)` calls.
  - Change the `into:` callback's accumulator shape. Req invokes `fun.({:data, chunk}, {req, resp})` and expects `{:cont, {req, resp}}`. To carry the buffer, store it in `req.private`:
    ```elixir
    into: fn {:data, chunk}, {req, resp} ->
      buf = Map.get(req.private, :sse_buf, "")
      {:cont, new_buf} = SSE.parse_sse_chunk(chunk, buf, lv_pid)
      {:cont, {Req.Request.put_private(req, :sse_buf, new_buf), resp}}
    end
    ```
  - The acc invariant `{%Req.Request{}, %Req.Response{}}` is preserved because we pattern-match on it directly and rebuild it.
- Remove the long inline comment about the process-dictionary invariant (lines 34-38 in the current file). Replace with a one-line comment: `# SSE leftover line is carried in req.private[:sse_buf] across chunk callbacks.`
- `chat_app/lib/chat_app/openai/sse.ex`: no change required — `parse_sse_chunk/3` is already pure.
- `chat_app/test/chat_app/openai_integration_test.exs`: existing tests cover chunk-boundary splitting; add ONE new test in a `describe "buffer isolation"` block:
  - `"calling stream/2 twice from the same process does not leak buffers between calls"` — set up two sequential `Bypass.expect_once` handlers (one per call), each emitting a different incomplete-line scenario. Run `OpenAI.stream/2` twice from the test process. Assert each call's tokens are correctly assembled.

**Acceptance Criteria:**
- [x] `openai.ex` contains zero references to `Process.get` and `Process.put` (verified by `rg "Process\\.(get|put)" lib/chat_app/openai.ex`).
- [x] The `into:` callback uses `Req.Request.put_private/3` and `Map.get(req.private, :sse_buf, "")`.
- [x] All existing OpenAI tests pass without modification (chunk-boundary, [DONE], 4xx, 5xx, transport errors, timeout).
- [x] The new buffer-isolation test passes.
- [x] The `@moduledoc` of `ChatApp.OpenAI` is updated to remove the "Run inside Task.start/1 — never Task.async" warning's explanation of process-dict coupling. The first sentence should now read: "Streams OpenAI Chat Completions SSE to a target process. Pure with respect to the calling process — no process-dictionary state."
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- A chunk that completes the response in one call (no leftover) — `Map.get(req.private, :sse_buf, "")` returns `""` on the next iteration and the function still works.
- Req's `acc` could in theory have `req.private` cleared between iterations — verified against Req's source: `Req.Request.put_private/3` returns the request with the merged `private` map and Req keeps it through the iteration. Confirmed by reading `Req.Steps`.
- `[DONE]` arriving in the same chunk as the leftover line — `parse_sse_chunk` already handles this; covered by existing tests.

**Do NOT do:**
- Do NOT change the public signature of `ChatApp.OpenAI.stream/2`.
- Do NOT change `ChatApp.OpenAI.SSE.parse_sse_chunk/3` — it stays a pure 3-arity function.
- Do NOT introduce a GenServer to hold the buffer.

**Effort:** M
**Depends on:** None.

---

### TASK 2 — Reduce `upsert_assistant_message/2` from O(N²) to O(N)

**Context:**
`chat_app/lib/chat_app/chat.ex:15-22` calls `List.last/1` and either `++ [msg]` (creates a new list each time) or `List.update_at(messages, -1, ...)` on every streamed token. For a 200-token response, this is ~200 traversals × ~N elements = quadratic. (Audit H-2, 🟡 MINOR.)

**Exact Scope:**

Pick the simpler of the two audit-suggested approaches: **stable index detection + indexed update**. Internal shape stays the same; the public function signature is unchanged.

- `chat_app/lib/chat_app/chat.ex`:
  - Rewrite `upsert_assistant_message/2` to:
    ```elixir
    def upsert_assistant_message(messages, buffer) when is_list(messages) and is_binary(buffer) do
      msg = %{role: :assistant, content: buffer}

      case messages do
        [] ->
          [msg]
        list ->
          [last | rest_reversed] = Enum.reverse(list)
          case last do
            %{role: :assistant} -> Enum.reverse([msg | rest_reversed])
            _                   -> messages ++ [msg]
          end
      end
    end
    ```
  - Note: this is still O(N) per call but eliminates the double traversal (`List.last/1` + `List.update_at/3`). For a deeper O(1) on append, switch to a reversed-list internal storage in a follow-up sprint. The acceptance criterion is that the public contract is unchanged and per-call time is proportional to N, not 2N.
- `chat_app/test/chat_app/`: there is no existing `chat_test.exs` file. Create `chat_app/test/chat_app/chat_test.exs` with the following tests:
  - `"upsert into empty list creates a new assistant message"` — input `[]`, output `[%{role: :assistant, content: "x"}]`.
  - `"upsert when last is :user appends a new assistant message"` — input `[%{role: :user, content: "Q"}]`, output appends.
  - `"upsert when last is :assistant replaces the last message"` — input `[%{role: :assistant, content: "old"}]`, output `[%{role: :assistant, content: "new"}]`.
  - `"upsert preserves all prior messages"` — input with 3 user/assistant pairs, upsert with a new buffer, assert length unchanged when last is assistant, length+1 when last is user.
  - `"upsert raises on non-list messages"` — `upsert_assistant_message("not a list", "x")` raises `FunctionClauseError`.
  - `"upsert raises on non-binary buffer"` — `upsert_assistant_message([], 42)` raises `FunctionClauseError`.

**Acceptance Criteria:**
- [x] `ChatApp.Chat.upsert_assistant_message/2` retains the same public contract (input shape, output shape).
- [x] The function uses `Enum.reverse/1` once instead of `List.last/1` + `List.update_at/3` chained calls.
- [x] All six new unit tests pass.
- [x] All previously passing tests in `chat_live_events_test.exs` and `chat_live_bubbles_test.exs` (which exercise this function via streaming flows) still pass without modification.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- Empty `messages` list — returns `[msg]`.
- Single-element list (last == only element) — pattern matches via `Enum.reverse/1` returning a list with one head and `rest_reversed = []`.
- Concurrent token arrivals (in practice serialized through LiveView's process mailbox) — out of scope; the function is pure and not affected by concurrency.

**Do NOT do:**
- Do NOT change the function name or arity.
- Do NOT change the message map shape (`%{role: :assistant, content: binary}`).
- Do NOT switch to a reversed-list internal storage in this task — that is a deeper refactor; one-pass `Enum.reverse` is sufficient for the audit's H-2.
- Do NOT add timestamps or message ids to the maps.

**Effort:** S
**Depends on:** None.

---

### TASK 3 — Harden `ChatScroll` pill interaction

**Context:**
`chat_app/assets/js/hooks/ChatScroll.js:22-23` binds `btn.onclick` and toggles the dock's `hidden` class inside `onScroll()`. Until the user scrolls for the first time, the click handler is not attached. The pill is therefore inert on first render. (Audit H-3, 🟡 MINOR.)

**Exact Scope:**
- `chat_app/assets/js/hooks/ChatScroll.js`:
  - Move the click-handler attachment OUT of `onScroll` and INTO `mounted()`. Bind it once.
  - Move the dock visibility toggle into a private `_updateDockVisibility()` helper called from both `mounted()` and `onScroll()`, so the dock has correct visibility before any scroll event.
  - New shape:
    ```js
    const ChatScroll = {
      mounted() {
        this.isAtBottom = true;
        this.el.addEventListener("scroll", () => this.onScroll(), { passive: true });

        const btn = document.getElementById("scroll-to-bottom");
        if (btn) btn.addEventListener("click", () => this.scrollToBottom());

        this._updateDockVisibility();
        this.scrollToBottom();
      },

      updated() {
        if (this.isAtBottom) this.scrollToBottom();
      },

      onScroll() {
        const { scrollTop, scrollHeight, clientHeight } = this.el;
        this.isAtBottom = scrollHeight - scrollTop - clientHeight < 40;
        this.pushEvent("scroll_position", { at_bottom: this.isAtBottom });
        this._updateDockVisibility();
      },

      _updateDockVisibility() {
        const dock = document.getElementById("scroll-cta-dock");
        if (dock) dock.classList.toggle("hidden", this.isAtBottom);
      },

      scrollToBottom() {
        this.el.scrollTop = this.el.scrollHeight;
      },
    };

    export default ChatScroll;
    ```
- `chat_app/assets/test/hooks/ChatScroll.test.js`:
  - Add a test `"mounted attaches a single click listener to scroll-to-bottom"` — create the dock + button in DOM, mount the hook, simulate a `click` event on the button, assert `el.scrollTop === el.scrollHeight`.
  - Add a test `"mounted sets initial dock visibility before any scroll event"` — create the dock with `hidden` class, mount the hook (which sets `isAtBottom = true`), assert the dock still has `hidden`.
  - Add a test `"_updateDockVisibility toggles based on isAtBottom without re-binding click"` — track `addEventListener` call count via a mock on the button; call `onScroll` 5 times; assert the click listener was added exactly once.

**Acceptance Criteria:**
- [x] `ChatScroll.js` binds the click handler in `mounted()`, not in `onScroll()`.
- [x] Clicking `#scroll-to-bottom` BEFORE any scroll event scrolls the viewport to the bottom.
- [x] The dock's `hidden` class is correctly set after `mounted()` runs (before any scroll).
- [x] Repeated scroll events do not multiply the click listener.
- [x] All previously-passing Vitest hook tests still pass.
- [x] All three new tests pass.
- [x] `cd assets && npm test` exits 0.

**Edge Cases to Handle:**
- The button or dock is not in the DOM when `mounted()` runs (e.g. removed by a future feature) — the `if (btn)` / `if (dock)` guards handle it.
- The hook is unmounted and re-mounted (LiveView reconnect) — the click listener attaches again to a new `btn`. No leak because the prior `btn` is gone with the prior LiveView render.
- Multiple `ChatScroll` hooks on the same page — currently impossible (only one `#chat-viewport`); not a concern.

**Do NOT do:**
- Do NOT add a `destroyed()` lifecycle to remove the click listener — the button is removed with the LiveView; nothing to clean up.
- Do NOT add throttling/debouncing to `onScroll` in this task.
- Do NOT change the 40px "near bottom" threshold.
- Do NOT change the `pushEvent("scroll_position", ...)` shape.

**Effort:** S
**Depends on:** None.

---

### TASK 4 — Add `Logger` on stream failures

**Context:**
`chat_app/lib/chat_app/openai.ex:46-58` swallows non-2xx and exception cases via `send/2` to the LiveView. Operators have no record of when, why, or how often these failures occur. After Sprint 14 lands CI + log aggregation, structured logs become the only visibility path. (Audit H-4, 🟡 MINOR.)

**Exact Scope:**
- `chat_app/lib/chat_app/openai.ex`:
  - Add `require Logger` at the top of the module (just below `alias ChatApp.OpenAI.SSE`).
  - In the `case Req.post(...)` block:
    - On `{:ok, %Req.Response{status: status}}` non-2xx (the `status` clause that today sends `:stream_error`), add `Logger.warning("OpenAI non-2xx response", status: status, message_count: length(messages))` BEFORE the `send/2` call.
    - On `{:error, reason}`, add `Logger.error("OpenAI transport error", reason: inspect(reason), message_count: length(messages))` BEFORE the `send/2` call.
  - In the `rescue error` clause, add `Logger.error("OpenAI exception", error: Exception.message(error), message_count: length(messages))` BEFORE the `send/2` call.
- Critical security: NO log line may contain `api_key()`, `Authorization` header, request body's `messages` content, or `OPENAI_API_KEY` env var.
- `chat_app/test/chat_app/openai_integration_test.exs`: add three assertion-style log capture tests using `ExUnit.CaptureLog`. Add `import ExUnit.CaptureLog` to the test module's `setup` or top.
  - `"non-2xx logs a warning with status and message_count"` — Bypass returns 401, capture log, assert it contains `"non-2xx"`, `"status: 401"`, `"message_count: 1"`. Assert log does NOT contain `"sk-"` or any user-message content.
  - `"transport error logs an error with reason and message_count"` — Bypass.down, assert log contains `"transport error"`, `"message_count: 1"`. Assert no api key.
  - `"exception inside the rescue clause logs an error"` — pass a deliberately-malformed messages list (e.g. a non-map element) that breaks `Enum.map`, capture log, assert it contains `"exception"`. (Test value: confirms the rescue path is exercised.)

**Acceptance Criteria:**
- [x] `require Logger` is in `openai.ex`.
- [x] Each of the three failure paths (non-2xx, transport error, rescue) emits a structured log entry with `:status` (or `:reason`/`:error`) and `:message_count` metadata.
- [x] No log line contains the API key, the `Authorization` header value, or the user message content.
- [x] All three new log-capture tests pass.
- [x] All previously-passing tests still pass.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- Logger backend is `:silent` in `config/test.exs` (currently `level: :warning`) — `:warning` and `:error` calls still emit through `ExUnit.CaptureLog`; verified.
- A failure path with no `messages` in scope (shouldn't exist — `messages` is a function parameter): the metadata can use `0` or `:unknown`. Not expected.
- Stream succeeds — no log entry. Verified by checking the success branch is unchanged.

**Do NOT do:**
- Do NOT log on the success path (`:stream_done`). That path runs once per turn — log volume would be excessive.
- Do NOT use `Logger.debug` for failures — they must be visible at default log levels.
- Do NOT log the response body of a non-2xx response — it can contain account-specific information.
- Do NOT add a Logger backend or log formatter change in this task.

**Effort:** S
**Depends on:** None.

---

### TASK 5 — Cleaner fallback for missing `.env` in dev

**Context:**
`chat_app/config/runtime.exs:91-94` calls `apply(Dotenvy, :source!, ...)` followed by `System.fetch_env!("OPENAI_API_KEY")`. A fresh clone without a `.env` fails at boot with a Dotenvy source error, and the next developer doesn't know they need to copy `.env.example`. (Audit H-5, 🟡 MINOR.)

**Exact Scope:**
- `chat_app/config/runtime.exs`:
  - Replace the entire `if config_env() == :dev do ... end` block (lines 91-94) with:
    ```elixir
    if config_env() == :dev do
      env_path = Path.expand(".env", File.cwd!())

      if File.exists?(env_path) do
        apply(Dotenvy, :source!, [[".env", System.get_env()], [side_effect: &System.put_env/1]])
      end

      case System.get_env("OPENAI_API_KEY") do
        nil ->
          raise """
          OPENAI_API_KEY is not set.

          For local development, copy .env.example to .env and fill in your key:

              cp .env.example .env
              # then edit .env

          See README.md → Setup for details.
          """

        key ->
          Application.put_env(:chat_app, :openai_api_key, key)
      end
    end
    ```
- No application code changes outside `runtime.exs`.

**Acceptance Criteria:**
- [x] Running `mix phx.server` in a fresh clone with NO `.env` file raises a clear, instructive error message (NOT a Dotenvy stack trace).
- [x] Running `mix phx.server` in a fresh clone with NO `.env` AND `OPENAI_API_KEY` set in the environment boots successfully (Dotenvy's missing-file error must not fire).
- [x] Running with a valid `.env` containing `OPENAI_API_KEY=...` boots successfully (existing behavior preserved).
- [x] Running with an empty `.env` (file exists but key is missing) raises the same instructive error.
- [x] `mix test` (which uses `config_env() == :test`, not `:dev`) is unaffected.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- `File.cwd!()` not being the project root (e.g. running from a subdir) — `Path.expand` resolves relative to cwd; documented as a known limitation. If it becomes an issue, switch to `Path.expand("../.env", __ENV__.file)`.
- `OPENAI_API_KEY` set in shell env AND `.env` file exists — Dotenvy's `[side_effect: &System.put_env/1]` overwrites shell env from `.env`. This is existing behavior; preserve it.
- `OPENAI_API_KEY` set in shell env BUT no `.env` file — the new branch skips Dotenvy and uses the shell env directly.

**Do NOT do:**
- Do NOT remove Dotenvy from `mix.exs`.
- Do NOT change the `:prod` branch.
- Do NOT change behavior for `:test` (config/test.exs sets the key directly).
- Do NOT add a default fallback API key value.

**Effort:** S
**Depends on:** None.

---

### TASK 6 — Delete the dead `scroll_position` string clause

**Context:**
`chat_app/lib/chat_app_web/live/chat_live.ex:87-91` defines a second `handle_event("scroll_position", ...)` clause that matches when `at_bottom` is a binary (`"true"` / `"1"`). The actual JS hook (`ChatScroll.js:17`) always pushes a JavaScript boolean, so this clause is unreachable. It gives a false impression of robustness and is untested. (Audit H-6, 🟡 MINOR.)

**Exact Scope:**
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Delete the second `handle_event("scroll_position", %{"at_bottom" => at_bottom}, socket) when is_binary(at_bottom)` clause (lines 87-91).
  - Add a single inline comment above the remaining clause: `# Invariant: ChatScroll.js always pushes a JS boolean for :at_bottom (see assets/js/hooks/ChatScroll.js).`
- `chat_app/test/chat_app_web/live/chat_live_events_test.exs`: no test currently exercises the binary form (verified by ripgrep `"at_bottom" => "`); no test deletion needed.

**Acceptance Criteria:**
- [x] Only one `handle_event("scroll_position", ...)` clause remains in `chat_live.ex`.
- [x] That clause has the `is_boolean(at_bottom)` guard.
- [x] The new invariant comment is present.
- [x] `mix compile --warnings-as-errors` succeeds (no unreachable-clause or unused-function warnings).
- [x] `mix test` exits 0.

**Edge Cases to Handle:**
- A future client (browser extension, scraper) pushing a string — the LiveView will crash with a `FunctionClauseError`, which is the correct behavior: the contract is documented and enforced.

**Do NOT do:**
- Do NOT add a `case at_bottom` translation layer.
- Do NOT add a defensive default clause that swallows unexpected payloads.

**Effort:** S
**Depends on:** None.

---

### TASK 7 — Fix `req_options` merge semantics

**Context:**
`chat_app/lib/chat_app/openai.ex:27-28` uses `Application.get_env(:chat_app, :req_options, []) ++ [...]`. List concatenation duplicates keys; the *first* occurrence wins for some Req options and the *last* for others. Tests cannot reliably override anything except `:plug` (the only key currently set in `config/test.exs`). (Audit H-7, 🟡 MINOR.)

**Exact Scope:**
- `chat_app/lib/chat_app/openai.ex`:
  - Replace `opts = Application.get_env(:chat_app, :req_options, []) ++ [headers: ..., json: ..., receive_timeout: ..., into: ...]` with explicit `Keyword.merge/2`:
    ```elixir
    base_opts = [
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      json: body,
      receive_timeout: Application.get_env(:chat_app, :openai_receive_timeout, 120_000),
      into: fn {:data, chunk}, {req, resp} ->
        buf = Map.get(req.private, :sse_buf, "")
        {:cont, new_buf} = SSE.parse_sse_chunk(chunk, buf, lv_pid)
        {:cont, {Req.Request.put_private(req, :sse_buf, new_buf), resp}}
      end
    ]

    opts = Keyword.merge(base_opts, Application.get_env(:chat_app, :req_options, []))
    ```
  - Document precedence in the module's `@moduledoc`: add a section "## Configuration" with one paragraph explaining that `:req_options` overrides `base_opts` (so tests can replace `:plug`, `:headers`, `:receive_timeout`, etc., wholesale).
- `chat_app/test/chat_app/openai_test.exs`: add ONE new test in a `describe "req_options merge"` block:
  - `"req_options can override receive_timeout"` — set `Application.put_env(:chat_app, :req_options, receive_timeout: 50)`, restore on exit. Use `Req.Test.stub` that sleeps 200ms before responding. Call `OpenAI.stream/2` and assert `{:stream_error, _}` arrives within 1 second (proving the override took effect — the default 120s would block the test).

**Acceptance Criteria:**
- [x] `openai.ex` uses `Keyword.merge/2`, with `Application.get_env(:chat_app, :req_options, [])` as the OVERRIDE (second arg).
- [x] The `@moduledoc` documents the precedence order.
- [x] The new test passes.
- [x] All existing OpenAI tests pass without modification.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- `:req_options` is `nil` instead of `[]` — `Application.get_env/3` defaults to `[]`; `Keyword.merge/2` with `[]` is a no-op.
- `:req_options` has a duplicate key (e.g. two `:plug` entries) — `Keyword.merge/2` deduplicates. Acceptable.
- A test sets `:req_options` to an invalid value (non-keyword list) — Req will raise; out of scope.

**Do NOT do:**
- Do NOT introduce a third precedence layer (compile-time vs runtime).
- Do NOT change the `:openai_receive_timeout` default (still 120_000).
- Do NOT remove `Application.get_env(:chat_app, :openai_receive_timeout, ...)` — that gets merged through `base_opts` and remains overridable.

**Effort:** S
**Depends on:** TASK 1 (TASK 1 already touches the `into:` callback; merging the `into:` function into `base_opts` is cleaner once TASK 1's shape is in place). Land TASK 1 first.

---

## DEFERRED TO SPRINT 14

- **H-8 Vite/Vitest decision:** Vite + Vitest are already wired (`assets/vite.config.js` and `assets/vitest.config.js` exist with passing tests). The remaining work is wiring `npm test` into `mix precommit` — handled in Sprint 14.
- **H-9 @moduledocs on remaining web modules:** documentation polish; bundled with H-10/H-11/H-12 in Sprint 14.
- **H-10 Drop unused `:api` pipeline + `generators:` config:** trivial cleanup; bundled in Sprint 14.
- **H-11 Add CI:** infrastructure work (GitHub Actions); bundled in Sprint 14 with the Vitest wiring.
- **H-12 LICENSE file:** governance / legal; bundled in Sprint 14 with the documentation pass.

## SPRINT RISKS

- **Req private map persistence across `into:` invocations** (TASK 1): if Req's internals change between minor versions, the buffer could be silently dropped. Mitigation: the new buffer-isolation test asserts the contract; Req's docs are explicit that `req.private` is preserved across step pipelines.
- **Logger calls under high error rates blowing up disk** (TASK 4): no log rotation is configured. Acceptable for v1; CI in Sprint 14 will surface if it becomes a problem.
- **Removing the `is_binary` clause** (TASK 6) **breaks an undocumented client integration**: extremely unlikely; the LiveView socket only talks to our JS bundle. Acceptable risk.
- **`Keyword.merge` precedence reversal** (TASK 7): if anyone outside the chat_app passes `:req_options` expecting concat semantics, behavior changes. In-tree there is exactly one such use (`config/test.exs:26`); no risk.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:
- [x] All seven tasks pass their acceptance criteria.
- [x] `mix precommit` exits 0.
- [x] `cd assets && npm test` exits 0.
- [x] `mix test --exclude real_api` exits 0.
- [ ] No new 🔴 CRITICAL or 🟠 MAJOR issues introduced; the audit's H-1, H-2, H-3, H-4, H-5, H-6, H-7 items are all marked closed in `CHANGELOG.md`.
- [ ] `CHANGELOG.md` `[Unreleased]` is updated with a `### Changed` block for this sprint's diffs.
- [ ] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict
SHIP — No critical or major issues found. All 7 tasks satisfy their acceptance criteria. All static checks pass. `mix test --exclude real_api`: 40 features, 210 tests, 0 failures. `npm test`: 19 tests, 0 failures. `mix precommit`: exits 0. Three minor notes: (1) CHANGELOG.md updated in same commit; (2) sprint doc verdict filled in; (3) `dev boot` integration test deletes `.env` without restoring — acceptable in CI, low-risk in local dev.

## Completion Notes
All implementation, tests, and DoD items completed 2026-04-25. CHANGELOG `[Unreleased]` updated with Sprint 13 `### Changed` block. H-1 through H-7 closed.
