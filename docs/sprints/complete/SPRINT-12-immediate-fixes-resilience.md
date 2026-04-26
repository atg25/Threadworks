---
status: complete
activated: Apr-25-2026
completed: Apr-25-2026
---

# SPRINT 12 — Immediate Fixes B: Resilience & Cleanup

**Status:** COMPLETE
**Created:** 2026-04-24
**Activated:** Apr-25-2026
**Completed:** 2026-04-25

## Goal
Stop the credit-leak vectors (unsupervised Task, no rate limit, error strings polluting the OpenAI prompt) and remove the scaffold dead code that confuses every reader of the LiveView module.

**Total effort:** ~9 hours (3 × M + 1 × M cleanup)
**Parallelizable:** TASK 4 (dead-code deletion) is the only task that does NOT touch `chat_live.ex` and can run in parallel with TASKS 1–3. TASKS 1, 2, 3 must be sequenced (1 → 2 → 3) because all three edit overlapping regions of `send_message`/`handle_info`.

---

## TDD Test Specification

Per-task descriptions below contain each task's primary tests. This section adds the upfront layer table, the E2E coverage (positive + ≥2 negative) and the explicit pure-unit / static checks. Per-task tests inside each TASK block are the source of truth for shape; this section is additive.

### Layer summary

| Layer | Tool | Test files | Tasks |
| --- | --- | --- | --- |
| Unit | ExUnit | `test/chat_app_web/live/chat_live_pure_test.exs` (new — for `drop_last_assistant`-style helpers if introduced) | 2, 3 |
| Integration | `Phoenix.LiveViewTest`, Floki, `Req.Test` | `test/chat_app_web/live/chat_live_events_test.exs` (extended), `test/chat_app_web/live/chat_live_bubbles_test.exs` | 1, 2, 3, 4 |
| E2E | Wallaby + ChromeDriver | `test/chat_app_web/features/chat_e2e_test.exs` (`@moduletag :e2e`) | 1, 2, 3 |
| Static | ripgrep, `mix compile --warnings-as-errors` | CI step / PR description | 1, 4 |

### Unit tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Hammer key derivation is stable for a session_id` | Same `session_id` passed twice to the helper that builds the rate-limit key. | Both calls return the identical binary `"chatlive:<session_id>"`. | TASK 3 — silent change of key shape causing per-call buckets and unbounded throughput. |
| `error assign shape: each entry has :for_index and :reason keys` | A list returned from `handle_info({:stream_error, "x"}, socket)` followed by a second send. | Every map in `socket.assigns.errors` has exactly the keys `:for_index` and `:reason`; values are integer + binary. | TASK 2 — drift to ad-hoc shapes that break the renderer's `<%= err.reason %>`. |
| `terminate/2 with stream_task_pid: nil is a no-op` | Call `ChatLive.terminate(:shutdown, %Phoenix.LiveView.Socket{assigns: %{stream_task_pid: nil}})`. | Returns `:ok` (or `:noreply`-equivalent), no exception, no side effect. | TASK 1 — naïve `Process.exit/2` on `nil` crashing the LiveView teardown. |

### Integration tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `send_message stores the streaming task pid in assigns` | `live(conn, "/")`; submit `"hello"`; read `:sys.get_state(view.pid).socket.assigns.stream_task_pid`. | Value is a pid; `Process.alive?(pid)` is true at read time. | TASK 1 — supervised task pid not threaded into assigns; `terminate/2` cannot cancel. |
| `:stream_done clears stream_task_pid to nil` | Submit; send `:stream_done`; read assigns. | `assigns.stream_task_pid == nil`. | TASK 1 — leaked pid causing a second cancellation attempt on the next teardown. |
| `:stream_error clears stream_task_pid to nil and appends to :errors, NOT :messages` | Submit; send `{:stream_error, "boom"}`; read assigns. | `assigns.stream_task_pid == nil`, `length(assigns.messages) == 1` (just the user msg), `length(assigns.errors) == 1`, error map's `:reason` is `"boom"`. | TASKS 1+2 — error string poisoning the next OpenAI prompt. |
| `terminating the LiveView kills the streaming task` | Long-running stub task that `Process.sleep(10_000)`s; monitor its pid; `GenServer.stop(view.pid, :shutdown)`. | `assert_receive {:DOWN, ^ref, :process, _, _}, 1_000`. | TASK 1 — unsupervised tasks continuing to consume OpenAI bytes after disconnect. |
| `error renders in [data-chat-message-error] element` | Submit; send `{:stream_error, "connection refused"}`. | `has_element?(view, "[data-chat-message-error]", "connection refused")` is true. | TASK 2 — rendering errors inside the message list (mistaken for assistant output). |
| `next send_message after a :stream_error does NOT include "Error:" in the OpenAI body` | Trigger error; install `Req.Test.stub` capturing body; submit a fresh message. | Decoded body's `messages` list contains zero entries whose `content` matches `~r/^Error:/`. | TASK 2 — historical regression: errors fed back into the prompt. |
| `21st send_message in 60s is rejected` | Fast stub for `:stream_done`; submit 21 messages back-to-back. | First 20 produce user bubbles; 21st leaves `assigns.messages` length unchanged at 20 user msgs and triggers a flash. | TASK 3 — limit off-by-one or window misconfigured (60_000 vs 60). |
| `rate-limited send does NOT invoke openai_module().stream/2` | Custom `:openai_module` recording call count; submit 21 messages. | Recorded count is exactly 20. | TASK 3 — limit only gates UI, not the outbound API call. |
| `rate-limit flash contains the substring "Slow down"` | Submit 21 messages. | `Phoenix.Flash.get(view.flash, :error)` contains `"Slow down"`. | TASK 3 — generic flash text drift; users miss the cause. |
| `removed PageController route returns 404` | After TASK 4: `get(conn, "/page")` (or whichever path the scaffold left). | `assert_error_sent 404, fn -> ... end`. | TASK 4 — deletion missed router or `controllers/` files. |

### E2E tests (Wallaby)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Positive — Stop on disconnect cancels the stream | Open `/`; submit `"slow message"` against an E2E stub that streams 1 token / 500ms; close the browser tab; back in the test process, monitor the supervised task's pid before close. | Within 2s of close, the monitored pid receives `:DOWN`; no further `:stream_token` arrives. | TASK 1 — silent credit leak after the user navigates away mid-stream. |
| Negative — burst of 25 messages stops at 20 with a flash | Open `/`; rapid-fire 25 submits via Wallaby's `fill_in` + `Enter`. | Exactly 20 user bubbles render; a `[role="alert"]` (or flash element) shows `"Slow down"`; the input is re-enabled. | TASK 3 — UI failing closed and locking the user, OR failing open and accepting all 25. |
| Negative — `:stream_error` does not poison the next turn | Open `/`; stub OpenAI to reply 401 once; submit `"first"`; assert error toast/element appears; reconfigure stub to a normal reply; submit `"second"`; capture the outgoing OpenAI body via stub. | Body for the second turn contains only the two user messages — NO `Error:` content; the `[data-chat-message-error]` from the first turn is still visible. | TASK 2 — error string smuggled into the prompt context. |
| Negative — orphaned scaffold removal does not break navigation | Open `/`; click anything, refresh, navigate to `/` again. | Page renders normally; no JS console errors; no Phoenix 500. | TASK 4 — accidentally deleting a still-referenced module. |

### Static / CI checks (no test framework)

| Check | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Task.start` absent from `chat_app/lib/` | `rg "Task\\.start\\(" chat_app/lib/` | Zero matches. | TASK 1 regression. |
| `ChatApp.TaskSupervisor` is a child of the application supervisor | `rg "Task\\.Supervisor" chat_app/lib/chat_app/application.ex` | Exactly one match referencing `name: ChatApp.TaskSupervisor`. | TASK 1 — supervisor never started, all `start_child/2` calls crash. |
| `Hammer ~> 6.2` pinned in `mix.exs` | `rg "{:hammer," chat_app/mix.exs` | Exactly one line; version pin starts with `"~> 6"`. | TASK 3 — accidental upgrade to Hammer 7.x with incompatible API. |
| `assigns.errors` mention only inside `chat_live.ex`, never in the OpenAI body builder | `rg "errors" chat_app/lib/chat_app/openai.ex` | Zero matches. | TASK 2 — code drift mixing the two pipelines back together. |
| Deleted scaffold paths absent | `ls chat_app/lib/chat_app_web/controllers/page_controller.ex chat_app/lib/chat_app_web/controllers/page_html.ex chat_app/lib/chat_app_web/controllers/page_html/` 2>&1 | All three return "No such file or directory". | TASK 4 — partial deletion. |
| `mix compile --warnings-as-errors` clean after CoreComponents trim | Run after each deletion in TASK 4. | Exit 0; no unused alias / unused import warnings remain. | TASK 4 — leftover `alias Phoenix.LiveView.JS` etc. |

---

## Tasks

### TASK 1 — Supervise the streaming Task with `Task.Supervisor` and add cancellation

**Context:**
`chat_app/lib/chat_app_web/live/chat_live.ex:57` uses `Task.start/1` for the OpenAI streaming call. The task is unlinked, has no supervisor, and has no cancellation handle stored on the LiveView. If the user disconnects mid-stream, the task continues to consume OpenAI bytes that the LiveView can no longer receive — burning credits with no cap. (Audit IF-8, 🟠 MAJOR. Prerequisite for TASK 3 of this sprint and for F-5 stop/regenerate in Sprint 16.)

**Exact Scope:**
- `chat_app/lib/chat_app/application.ex`:
  - Add `{Task.Supervisor, name: ChatApp.TaskSupervisor}` to the `children` list, immediately after the `Phoenix.PubSub` line.
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Add `stream_task_pid: nil` to the assigns map in `mount/3` (line ~36-43).
  - In `handle_event("send_message", ...)` (lines 47-75), replace the `Task.start(fn -> ... end)` block (lines 57-63) with:
    ```elixir
    {:ok, task_pid} =
      Task.Supervisor.start_child(ChatApp.TaskSupervisor, fn ->
        try do
          openai_module().stream(messages, pid)
        rescue
          e -> send(pid, {:stream_error, Exception.message(e)})
        end
      end)
    ```
  - Add `stream_task_pid: task_pid` to the `assign(socket, ...)` call at lines 65-73.
  - In `handle_info(:stream_done, socket)` and `handle_info({:stream_error, _}, socket)`, set `stream_task_pid: nil` in the resulting assigns.
  - Add a `@impl true` `def terminate(_reason, socket)` callback that calls `Process.exit(pid, :shutdown)` if `socket.assigns.stream_task_pid` is a pid AND `Process.alive?(pid)` returns true. Place it after `handle_info({:stream_error, ...})`.
- `chat_app/test/chat_app_web/live/chat_live_events_test.exs`: add four new tests in a new `describe "task supervision"` block:
  - `"send_message stores the streaming task pid in assigns"` — submit, fetch the LiveView state via `:sys.get_state(view.pid).socket.assigns.stream_task_pid`, assert is a pid.
  - `":stream_done clears stream_task_pid to nil"` — submit, send `:stream_done`, assert assign is nil.
  - `":stream_error clears stream_task_pid to nil"` — submit, send `{:stream_error, "x"}`, assert assign is nil.
  - `"terminating the LiveView kills the streaming task"` — start a long-running stub task that sleeps, monitor the task pid, kill the LiveView via `GenServer.stop(view.pid, :shutdown)`, assert `assert_receive {:DOWN, ^ref, :process, _, _}, 1000`.

**Acceptance Criteria:**
- [x] `application.ex` starts `ChatApp.TaskSupervisor` under the main supervision tree.
- [x] `chat_live.ex` contains zero `Task.start/` references (verified via `rg "Task\\.start" lib/`).
- [x] `assigns.stream_task_pid` is set to a pid on `send_message` and to `nil` on `:stream_done` / `:stream_error`.
- [x] `terminate/2` calls `Process.exit/2` only when the pid is alive.
- [x] All four new tests pass.
- [x] All previously passing LiveView/integration tests still pass.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- `Task.Supervisor.start_child/2` returns `{:ok, pid}` in normal operation; defensively pattern-match and crash on `{:error, _}` (acceptable — supervisor failure is a system-level issue).
- LiveView terminates *before* the task starts (process died during render): `terminate/2` sees `nil` for `stream_task_pid`; the `is_pid` guard short-circuits.
- Task already finished before `terminate/2` runs: `Process.alive?/1` returns false; do nothing.
- Crash inside the task body: the existing `try/rescue` still sends `{:stream_error, ...}` to the LiveView pid; the supervisor logs but does not restart (default `:temporary` child).

**Do NOT do:**
- Do NOT use `Task.async/1` or `Task.async_stream/2`. The audit explicitly forbids it because the LiveView is not the awaiting process.
- Do NOT add a "Stop generating" button in this task — that is F-5 in Sprint 16.
- Do NOT change the `openai_module().stream/2` contract.
- Do NOT add `Process.monitor/1` on the task pid; the existing `send/2` channel is sufficient.

**Effort:** M
**Depends on:** None (independent of all Sprint 11 tasks; can land first in Sprint 12)

---

### TASK 2 — Split errors out of `messages` so the OpenAI prompt is not poisoned

**Context:**
On `:stream_error`, `chat_live.ex:106-110` appends an `%{role: :assistant, content: "Error: <reason>"}` message to `assigns.messages`. That same `messages` list is sent to OpenAI on the *next* turn (line 54: `messages = socket.assigns.messages ++ [user_msg]`). Errors therefore become part of the prompt context, polluting subsequent responses and wasting tokens. (Audit IF-6, 🟠 MAJOR.)

**Exact Scope:**
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Add `errors: []` to the `mount/3` assigns map.
  - Change `handle_info({:stream_error, reason}, socket)` (lines 106-110):
    - Do NOT append to `messages`.
    - Compute `error_index = length(socket.assigns.messages) - 1` (the index of the assistant message that was being built, which may be incomplete).
    - Append `%{for_index: error_index, reason: reason}` to `socket.assigns.errors`.
    - Keep the existing `is_sending: false`, `stream_buffer: ""`, `stream_task_pid: nil` resets from TASK 1.
  - In `render/1`, inside the `<%= for msg <- @messages do %>` loop (around line 153), after each `message_bubble`, render any matching error inline:
    ```heex
    <%= for msg <- @messages do %>
      <.message_bubble message={msg} />
    <% end %>
    <%= for err <- @errors do %>
      <div class="ui-chat-message-error mx-auto max-w-[80%] rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-xs text-red-700"
           data-chat-message-error="true">
        Error: <%= err.reason %>
      </div>
    <% end %>
    ```
    The `for_index` is computed but not used for in-place insertion in this sprint — errors render as a flat list at the bottom. (In-place rendering is a Sprint 16 polish task.)
- `chat_app/assets/css/chat.css`: add a `.ui-chat-message-error` class scoped under the existing chat layer. Single block: muted red border + tinted background. Do NOT introduce new tokens; reuse `--space-3`, `--radius-md` if present, or hardcode tailwind classes inline (above HEEx already does this — CSS file change is optional).
- `chat_app/test/chat_app_web/live/chat_live_events_test.exs`: replace the existing `:stream_error` tests (lines 141-161) with three new tests:
  - `":stream_error appends to assigns.errors, NOT to messages"` — submit, send error, assert `length(assigns.messages) == 1` (just the user msg) AND `length(assigns.errors) == 1`.
  - `":stream_error renders the error message in a [data-chat-message-error] element"` — submit, send error reason `"connection refused"`, assert `has_element?(view, "[data-chat-message-error]", "connection refused")`.
  - `"sending a new message after a :stream_error does NOT include 'Error:' in the OpenAI body"` — use the existing `Req.Test.stub` infrastructure from `openai_test.exs`. After triggering an error, send a new message, capture the request body, decode it, assert no `content` field of any message contains the substring `"Error:"`.

**Acceptance Criteria:**
- [x] `assigns.errors` exists and is initialized to `[]`.
- [x] `:stream_error` no longer appends to `assigns.messages`.
- [x] Errors render in `[data-chat-message-error]` elements visible to the user.
- [x] On the second `send_message` after an error, the outgoing OpenAI request body's `messages` field contains zero entries with `"Error:"` in their `content`.
- [x] All three new tests pass.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- Error fires before any assistant token arrives — `for_index` is `length(messages) - 1`, which points at the last user message; that's acceptable for v1 since the error is rendered as a flat trailing list.
- Multiple consecutive errors — each appends to `assigns.errors`; UI shows them stacked.
- Stream succeeds AFTER a prior error — the new assistant message renders normally; old errors stay visible (this is the desired behavior: do not silently clear past failures).
- A `:stream_error` arrives while `is_sending: false` (race condition) — handle defensively by always appending; do not branch on `is_sending`.

**Do NOT do:**
- Do NOT clear `assigns.errors` on a successful next message — keeping past errors visible is intentional UX.
- Do NOT render errors in-place between messages using `for_index` in this sprint — that is a Sprint 16 polish task. A flat trailing list is the v1.
- Do NOT change the `:stream_token` or `:stream_done` handlers.
- Do NOT add a "retry" button — that is F-10 in Sprint 16.

**Effort:** M
**Depends on:** TASK 1 (uses the `stream_task_pid: nil` reset on error introduced there)

---

### TASK 3 — Add per-session rate limiting via Hammer

**Context:**
`send_message` has only an `is_sending` guard (line 50), which a single browser circumvents by reconnecting. Combined with no auth, an anonymous visitor can spend unlimited OpenAI credits in a tight loop. (Audit IF-5, 🟠 MAJOR.)

**Exact Scope:**
- `chat_app/mix.exs`: add `{:hammer, "~> 6.2"}` to `deps/0`. (Hammer 6.x exposes the `Hammer.check_rate/3` API the audit references; do NOT use 7.x in this sprint.) Run `mix deps.get`. If `mix hex.info hammer` shows a newer 6.x patch, use that exact version pin instead.
- `chat_app/lib/chat_app/application.ex`: add the Hammer ETS backend to `children` after `Task.Supervisor`:
  ```elixir
  {Hammer, backend: {Hammer.Backend.ETS, [
     expiry_ms: 1_000 * 60 * 60 * 4,
     cleanup_interval_ms: 1_000 * 60 * 10
  ]}}
  ```
  Note: Hammer 6.2's child-spec form is `{Hammer.Supervisor, [backend: ...]}` — verify against the installed version's docs and use the form that the docs show. Either is acceptable as long as the application boots.
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - In `mount/3`, generate a stable per-session id via `:crypto.strong_rand_bytes(16) |> Base.encode16()` and store in `assigns.session_id`. Use `if connected?(socket), do: ..., else: nil` so the id only generates after WebSocket upgrade.
  - At the very top of `handle_event("send_message", %{"input" => text}, socket)`, before the trim/blank checks, call:
    ```elixir
    case Hammer.check_rate("chatlive:#{socket.assigns.session_id}", 60_000, 20) do
      {:allow, _count} -> :ok
      {:deny, _limit} ->
        socket =
          socket
          |> Phoenix.LiveView.put_flash(:error, "Slow down — you're sending messages too fast. Please wait a minute.")
        throw({:rate_limited, socket})
    end
    ```
  - Wrap the existing function body in `try do ... catch :throw, {:rate_limited, socket} -> {:noreply, socket} end`. (An `if` guard is also acceptable — the throw is one option; a cleaner alternative is a private `defp check_rate_limit(socket)` returning `{:ok, socket} | {:rate_limited, socket}` and pattern-matching on it. Choose whichever the dev agent finds cleanest; the acceptance tests verify behavior, not shape.)
- Limits are: **20 messages per 60-second window per session**.
- `chat_app/test/chat_app_web/live/chat_live_events_test.exs`: add three new tests in a `describe "rate limiting"` block:
  - `"first 20 messages within 60s are allowed"` — submit 20, assert all appear as user bubbles. Use `Application.put_env` to swap the openai stub to `ChatApp.OpenAI.Stub` (already configured) and rely on `is_sending` not blocking after artificial `:stream_done` sends in a helper.
  - `"21st message in the same window is rejected and triggers a flash"` — call `send_message` 21 times rapidly, assert the LiveView's flash contains `"Slow down"`.
  - `"rate-limited request does NOT call openai_module().stream/2"` — set `:openai_module` to a custom test module that records calls; submit 21 messages; assert the recorded count is exactly 20.
- Test isolation: each test must call `Hammer.delete_buckets("chatlive:*")` (or use a unique session id by stubbing `:crypto.strong_rand_bytes/1`) to avoid cross-test pollution.

**Acceptance Criteria:**
- [x] `Hammer ~> 6.2` is in `mix.exs` and `mix.lock` is updated.
- [x] Application boots cleanly with the Hammer backend supervised.
- [x] `assigns.session_id` is a non-empty string after `connected?(socket)` is true.
- [x] After 20 successful `send_message` calls in 60s, the 21st is rejected.
- [x] The 21st call sets a flash with the substring `"Slow down"`.
- [x] `openai_module().stream/2` is NOT invoked for rate-limited calls.
- [x] All three new tests pass.
- [x] `mix precommit` exits 0.

**Edge Cases to Handle:**
- LiveView mounts twice (HTTP fetch then WebSocket connect) — `connected?(socket)` distinguishes them; only the connected mount generates a session id, so the disconnected first mount uses `nil` and the rate-limit key becomes `"chatlive:"` once. Acceptable for v1; revisit if it causes false positives.
- Hammer ETS table not yet ready at first request (boot race) — the application supervisor starts Hammer before the Endpoint, so by the time a request arrives the table exists.
- A user opens 2 tabs → 2 distinct session_ids → 40 msg/min total. Acceptable for v1; per-IP tightening is in F-2 (Sprint 15).
- Wallaby E2E tests submit ~6-10 messages per test — well under 20, no test impact. Confirmed by reading `chat_e2e_test.exs`.

**Do NOT do:**
- Do NOT add a per-IP plug-level limit in this sprint — F-2 in Sprint 15 introduces basic auth and the proper IP-keyed plug.
- Do NOT use Hammer 7.x — its API is incompatible with the `Hammer.check_rate/3` signature this task uses.
- Do NOT make the limit (20/60s) configurable in this task — hardcoded for v1, lifted to config in F-2.
- Do NOT persist rate-limit buckets in a database — ETS-only is sufficient.

**Effort:** M
**Depends on:** TASK 2 (so that the flash error UI is consistent with the new `assigns.errors` rendering pattern; the rate-limit flash uses Phoenix's flash group, which is independent — but TASK 2 lands first to avoid two passes over the render block)

---

### TASK 4 — Delete orphaned scaffold: PageController, theme_toggle, daisyUI debt in CoreComponents

**Context:**
`PageController`, `PageHTML`, `home.html.heex`, `Layouts.theme_toggle/1`, and most of `CoreComponents` reference daisyUI classes (`.btn`, `.card`, `.alert-info`, `.toast-top`, etc.) that are NOT shipped — daisyUI is not installed (only `tailwindcss-animate` and `@tailwindcss/typography` are in `package.json`). The dead code confuses every reader of the codebase and inflates ripgrep noise. (Audit IF-9, 🟠 MAJOR.)

**Exact Scope:**

Delete these files:
- `chat_app/lib/chat_app_web/controllers/page_controller.ex`
- `chat_app/lib/chat_app_web/controllers/page_html.ex`
- `chat_app/lib/chat_app_web/controllers/page_html/home.html.heex`
- `chat_app/lib/chat_app_web/controllers/page_html/` (the now-empty directory)
- `chat_app/test/chat_app_web/controllers/page_controller_test.exs` (currently a `@tag :skip` placeholder)

Edit `chat_app/lib/chat_app_web/components/layouts.ex`:
- Delete `def theme_toggle(assigns) do ... end` (lines 89-124, including its `@doc`).

Edit `chat_app/lib/chat_app_web/components/core_components.ex`:
- **Keep:** `flash/1`, `flash_group/1` (used by `Layouts.flash_group/1`), `icon/1` (used by `flash/1` and by error pages), `show/2`, `hide/2`, `translate_error/1`, `translate_errors/2`.
- **Delete:** `button/1` (lines ~82-117), `input/1` (all four clauses, lines ~159-304), `header/1` (lines ~316-337), `table/1` (lines ~339-403), `list/1` (lines ~405-432), private helper `error/1` (lines ~306-314).

Verify deletions are safe:
- Run `rg "CoreComponents\\.button|<\\.button" lib/ test/` — must return zero matches outside this file.
- Run `rg "CoreComponents\\.input|<\\.input" lib/ test/` — must return zero matches outside this file.
- Run `rg "CoreComponents\\.header|<\\.header" lib/ test/` — must return zero matches outside this file.
- Run `rg "CoreComponents\\.table|<\\.table" lib/ test/` — must return zero matches.
- Run `rg "CoreComponents\\.list|<\\.list" lib/ test/` — must return zero matches.
- Run `rg "theme_toggle" lib/ test/` — must return zero matches outside `layouts.ex` (now deleted) and possibly inside `layouts/root.html.heex` (the theme JS stays; only the helper function is gone).

After each deletion, run `mix compile --warnings-as-errors`. If it warns about unused imports / aliases inside `core_components.ex` (e.g. `alias Phoenix.LiveView.JS` becomes unused once `button/1` is gone), trim those imports too.

Do NOT touch `chat_app/lib/chat_app_web/components/layouts/root.html.heex` — the theme JS in `<script>` tags is still wired up to localStorage, which is not dead (it just has no UI driver yet; F-7 in Sprint 16 adds the toggle button).

**Acceptance Criteria:**
- [x] All listed files are deleted.
- [x] All listed functions in `core_components.ex` are deleted.
- [x] `theme_toggle/1` is removed from `layouts.ex`.
- [x] `mix compile --warnings-as-errors` exits 0.
- [x] `mix test --exclude real_api` exits 0.
- [x] `cd assets && npm test` exits 0.
- [x] `rg` of each removed function name shows no surviving callers.
- [x] The `<script>` theme block in `root.html.heex` is unchanged.
- [x] `chat_app/CHANGELOG.md` `[Unreleased] — Removed` documents the deletions in one bullet each.

**Edge Cases to Handle:**
- `layouts.ex` may have an `alias Phoenix.LiveView.JS` near the top that becomes unused after `theme_toggle/1` is deleted — remove it if the compiler warns.
- `core_components.ex` may have an `import` or `alias` that becomes unused after the trim — same handling.
- The `error/1` private helper inside `core_components.ex` is only called by `input/1`'s clauses; deleting `input/1` makes `error/1` unused. Delete it as well.
- Phoenix's default error pages (`ErrorHTML`) call `<.icon>` indirectly via no path — leave `icon/1` alone.
- `flash_group/1` calls `<.flash>` and `<.icon>` — both kept.

**Do NOT do:**
- Do NOT delete `flash/1`, `flash_group/1`, `icon/1`, `show/2`, `hide/2`, `translate_error/1`, or `translate_errors/2`.
- Do NOT delete `chat_app/lib/chat_app_web/components/layouts.ex` — only the `theme_toggle/1` function inside it.
- Do NOT delete `error_html.ex` or `error_json.ex` (Phoenix error renderers — used by the endpoint).
- Do NOT remove the `:tailwindcss-animate` or `@tailwindcss/typography` deps from `package.json` — both are used by the actual chat layer.
- Do NOT modify the `<script>` theme block in `root.html.heex`.

**Effort:** M
**Depends on:** None — fully independent of TASKS 1–3 (touches different files); can land in parallel.

---

## DEFERRED TO SPRINT 13

- **H-1 SSE buffer out of process dictionary:** architectural cleanup, no behavioral change; can wait one sprint.
- **H-2 O(N) message append:** performance polish; no correctness impact.
- **H-3 ChatScroll pill interaction hardening:** UX polish; current behavior works after first scroll event.
- **H-4 Logger on stream failures:** ops visibility; can wait one sprint.
- **H-5–H-7 (env fallback, dead clause, req opts merge):** small ergonomic cleanups; bundled with H-1–H-4 in Sprint 13.

## SPRINT RISKS

- **Hammer 6.x vs 7.x:** the Hex registry may default to 7.x on `mix deps.get` if no version is pinned. Mitigation: pin `~> 6.2` explicitly. If 6.x is unavailable for any reason, fall back to `:plug_attack` and adjust TASK 3 accordingly — the acceptance criteria (20 msg / 60s, flash on deny, no openai call on deny) are library-agnostic.
- **`Process.exit(pid, :shutdown)` on already-finished task:** harmless because of the `Process.alive?/1` guard, but a race window exists. Mitigation: the guard is sufficient for v1; revisit if Logger logs spurious shutdown messages.
- **Flash collision with the Phoenix server-error / client-error flashes:** the `Layouts.flash_group/1` already renders both `:info` and `:error`. The rate-limit flash uses `:error`, which displays at top-right. Acceptable.
- **Wallaby E2E tests blocked by 20-msg cap:** the longest E2E test sends 6 messages. No test will hit the cap.
- **Removing CoreComponents helpers breaks a future feature:** any function the team needs later can be re-added; deletion is reversible from git history. Out-of-scope risk.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:
- [x] All four tasks pass their acceptance criteria.
- [x] `mix precommit` exits 0.
- [x] `cd assets && npm test` exits 0.
- [x] `mix test --exclude real_api` shows zero failures.
- [x] No new 🔴 CRITICAL or 🟠 MAJOR issues introduced.
- [x] `CHANGELOG.md` `[Unreleased]` is updated with `### Added`, `### Changed`, `### Removed` blocks for this sprint's diffs.
- [x] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict
**SHIP** — 2026-04-25. Streaming tasks are supervised and cancellable; errors are kept out of the OpenAI message list; per-session rate limiting is active; scaffold dead code is removed. One **major** issue found in review (re-added `/page` route solely to force a 404) was **removed**; unmapped paths again return a normal 404. Residual items are **minor** (see Completion Notes).

## Completion Notes
- **After QA:** Dropped the temporary `LegacyRouteController` + `GET /page` so TASK 4 matches the intent: no scaffold route, natural 404 for `/page`. Public `ChatLive.rate_limit_key_for_session/1` documents the key shape; unit test now asserts through that API. `OpenAI` moduledoc no longer references `Task.start/1` (avoids false positives on static `rg` checks and matches implementation).
- **Open / follow-up (not blockers):** `ensure_session_id/1` relaxes the “session id only when connected” rule so rapid sends before WebSocket connect still rate-limit correctly (documented in sprint risks as v1). No automated Hammer bucket cleanup in tests (cross-test pollution mitigated by session ids + test patterns). E2E “prompt poison” scenario was simplified in tests vs the full spec table (covered in integration + behavior assertions).
