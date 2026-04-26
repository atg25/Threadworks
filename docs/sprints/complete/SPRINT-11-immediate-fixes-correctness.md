---
status: complete
activated_date: Apr-25-2026
completed: Apr-25-2026
---

# SPRINT 11 — Immediate Fixes A: Correctness & XSS

**Status:** COMPLETE
**Created:** 2026-04-24
**Activated:** Apr-25-2026
**Completed:** Apr-25-2026

## Goal
Eliminate the three deploy-blocking defects (Mix.env runtime crash, Markdown XSS, leaked OpenAI key posture) plus two surface-level correctness items (textarea markup, hardcoded model) so the codebase can be released and Sprint 12 can layer resilience on a safe base.

**Total effort:** ~5 hours (5 × S)
**Parallelizable:** All five tasks touch independent files; they may run concurrently on separate branches and merge in any order.

---

## TDD Test Specification

The per-task descriptions below contain each task's primary integration tests. This section adds the upfront layer table (previously missing from planned sprints) and backfills the E2E paths (positive + ≥2 negative) and explicit pure-unit coverage. Per-task tests inside each TASK block are the source of truth for shape; this section is additive.

### Layer summary

| Layer | Tool | Test files | Tasks |
| --- | --- | --- | --- |
| Unit | ExUnit | `test/chat_app/markdown_test.exs`, `test/chat_app/openai_test.exs` | 2, 4 |
| Integration | `Phoenix.LiveViewTest`, Floki, `Req.Test` | `test/chat_app_web/live/chat_live_test.exs`, `chat_live_events_test.exs`, `chat_live_bubbles_test.exs` | 1, 2, 4, 5 |
| E2E | Wallaby + ChromeDriver | `test/chat_app_web/features/chat_e2e_test.exs` (`@moduletag :e2e`) | 1, 2, 5 |
| Static | ripgrep, `git log -S` | CI step / PR description | 1, 3, 4, 5 |

### Unit tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `to_html/1 escapes embedded <script> tags` | `"<script>alert('xss')</script>"` | Result contains `&lt;script&gt;`; no literal `<script>` substring. | TASK 2 regression — flip back to `escape: false` reopens XSS vector. |
| `to_html/1 escapes & in plain text without doubling` | `"AT&T"` | Result contains `AT&amp;T`, not `AT&amp;amp;T`. | Earmark/`Phoenix.HTML` config drift double-escaping. |
| `to_html/1 still emits <pre><code> for fenced blocks` | ` "```\nlet x = 1\n```" ` | Result contains `<pre><code>` and `let x = 1`. | Over-aggressive escaping breaking code rendering. |
| `to_html/1 escapes raw HTML inside fenced blocks` | ` "```\n<b>x</b>\n```" ` | Body contains `&lt;b&gt;`, not literal `<b>`. | Fast path bypassing escape inside code fences. |
| `openai_model/0 reads :openai_model with default fallback` | unset env, then `Application.put_env(:chat_app, :openai_model, "gpt-test")` | Returns `"gpt-4o"` first, `"gpt-test"` second. | TASK 4 regression — hard-coded `"gpt-4o"` reappearing inline. |

### Integration tests

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `mount/3 ignores ?hero_state=false when override is off` | `Application.put_env(:chat_app, :allow_hero_override, false)`; `live(conn, "/?hero_state=false")` | `has_element?(view, "[data-homepage-chat-intro]")` is `true`. | TASK 1 — query-string override leaking into prod. |
| `mount/3 honors ?hero_state=false when override is on` | `Application.put_env(:chat_app, :allow_hero_override, true)`; `live(conn, "/?hero_state=false")` | Hero element absent from view. | Test-harness escape hatch silently breaking. |
| `assistant bubble renders escaped <script> as text` | Stub OpenAI to reply `"<script>alert(1)</script>"`; submit message; await `:stream_done`. | Rendered HTML contains `&lt;script&gt;`; no `<script>` element in Floki parse. | TASK 2 escape flag drift end-to-end. |
| `OpenAI.stream/2 sends configured :openai_model in body` | `Application.put_env(:chat_app, :openai_model, "gpt-test-12345")`; `Req.Test.stub` captures body. | Decoded body's `"model"` equals `"gpt-test-12345"`. | TASK 4 — model literal not flowing through to the wire. |
| `composer renders empty paired textarea on first mount` | Mount `/`; parse with Floki. | `<textarea id="chat-input">` exists; `Floki.text/1` empty after trim; no `value` attribute. | TASK 5 — invalid `<textarea value="">` reappearing. |
| `composer body round-trips literal { } characters` | Trigger `phx-change="update_input"` with `"let x = {a: 1}"`; re-render. | Textarea body contains literal `{a: 1}`; no HEEx parse error. | Migration to `{@input}` HEEx form silently breaking literal braces. |

### E2E tests (Wallaby)

| Test name | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| Positive — hero visible on cold load | Open `/` with default config (no override). | `[data-homepage-chat-intro]` visible; composer empty; no JS console errors. | TASK 1 — hero hidden by accident in prod-shaped config. |
| Negative — query-string override has no effect when override is off | `Application.put_env(:chat_app, :allow_hero_override, false)`; open `/?hero_state=false`. | Hero still visible; LiveView did not crash. | Reintroduction of `Mix.env()` runtime gate. |
| Negative — model `<script>` payload is rendered as text, not executed | Stub `openai_module` to reply `"<script>window.__pwned=1</script>"`; submit any prompt. | Literal `<script>` text visible inside bubble; `executeScript("return !!window.__pwned")` returns `false`; no `<script>` child of the bubble in DOM. | TASK 2 escape regression — would execute script in real browsers. |
| Positive — submit clears the textarea body | Type `"hello"`; press Enter. | `el.value` of `#chat-input` becomes `""`; SSR body of textarea also empty after LiveView patch. | TASK 5 regression — `value={@input}` reappearing breaks SSR / a11y / view-source. |
| Negative — composer accepts literal braces without crash | Type `"let x = {a: \"{}\"}"`; press Enter. | LiveView does not crash; outgoing message body contains the literal text verbatim. | Future curly HEEx interpolation form regression. |

### Static / CI checks (no test framework)

| Check | Inputs | Expected | Guards against |
| --- | --- | --- | --- |
| `Mix.env` / `Mix.target` absent from runtime code | `rg "Mix\\." chat_app/lib/` | Zero matches in `lib/`. | TASK 1 — silent reintroduction of `Mix` runtime call. |
| OpenAI key never committed | `git log --all --full-history -S "sk-proj-" -- chat_app` | Zero matches. | TASK 3 — secret slipping into git history. |
| `runtime.exs` env vars documented in `.env.example` | Diff `rg "System\\.(fetch_env!|get_env)" config/runtime.exs` keys against `.env.example`. | Every key present (commented or not). | TASK 3 documentation drift over time. |
| Hard-coded `"gpt-4o"` outside config default | `rg '"gpt-4o"' chat_app/lib/` | Single match: the `Application.get_env/3` default in `openai.ex`. | TASK 4 regression — back-channel literal. |
| `value=` absent on any `<textarea>` | `rg 'textarea[^>]*value=' chat_app/lib/` | Zero matches. | TASK 5 regression. |

---

## Tasks

### TASK 1 — Replace `Mix.env()` runtime call with `:allow_hero_override` app-env flag

**Context:**
`chat_app/lib/chat_app_web/live/chat_live.ex:33` calls `Mix.env() == :test` inside `mount/3`. `Mix` is a build-time module and is not packaged into a `mix release`, so the first browser request to a released build crashes the LiveView and renders a blank page (Audit IF-1, 🔴 CRITICAL).

**Exact Scope:**
- `chat_app/lib/chat_app/application.ex` (or `config/config.exs`): no change required, default falls to `false` via `Application.get_env/3`'s third argument.
- `chat_app/config/test.exs`: add `config :chat_app, :allow_hero_override, true` (group with the other `:chat_app` test configs).
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Replace line 33 (`hero_state = if Mix.env() == :test, do: parse_hero_state(params), else: true`) with:
    ```elixir
    hero_state =
      if Application.get_env(:chat_app, :allow_hero_override, false) do
        parse_hero_state(params)
      else
        true
      end
    ```
  - Keep `defp parse_hero_state/1` clauses (lines 344–346) unchanged — they are still gated, just by app env now.
- `chat_app/test/chat_app_web/live/chat_live_test.exs`: existing test `"hero is hidden when hero_state is false"` (~line 151) must continue to pass (it relies on `?hero_state=false` working in the test env; the new flag preserves that).
- Add **one new regression test** in `chat_live_test.exs` named `"hero_state defaults to true regardless of params when allow_hero_override is false"`:
  - Use `Application.put_env(:chat_app, :allow_hero_override, false)` inside the test, restore via `on_exit/1`.
  - `live(conn, "/?hero_state=false")` and assert `has_element?(view, "[data-homepage-chat-intro]")` is true.

**Acceptance Criteria:**
- [x] `chat_live.ex` contains zero references to `Mix.env`, `Mix.target`, or any `Mix.*` call (verified via `rg "Mix\\." lib/`).
- [x] `Application.get_env(:chat_app, :allow_hero_override, false)` is the sole gate on `parse_hero_state/1`.
- [x] `config/test.exs` sets `:allow_hero_override` to `true`.
- [x] All previously passing tests in `test/chat_app_web/live/` still pass.
- [x] The new regression test passes.
- [x] `MIX_ENV=prod mix compile` produces no warnings (Mix is still loadable at compile time, just not at runtime — confirm with `MIX_ENV=prod mix compile --warnings-as-errors`).
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- `Application.get_env/3` returning `nil` when the key is absent — the third-argument default `false` covers this; do NOT call `Application.fetch_env!/2`.
- `params` map missing the `hero_state` key — `parse_hero_state(_params)` already returns `true` (line 346); leave unchanged.
- Test isolation: the new test must restore the env to its prior value via `on_exit`, otherwise downstream `async: false` tests will see a leaked `false`.

**Do NOT do:**
- Do NOT delete `parse_hero_state/1` — the audit suggested it as an option but the test harness still uses `?hero_state=false`.
- Do NOT add a `:dev` override; only `:test` should set the flag to `true`.
- Do NOT change the default value of `hero_state` from `true` for cold mounts.

**Effort:** S
**Depends on:** None

---

### TASK 2 — Close Markdown XSS hole (`escape: false` → `escape: true`)

**Context:**
`chat_app/lib/chat_app/markdown.ex:18` runs Earmark with `escape: false`, and `chat_live.ex:269` then `raw/1`s the output into the assistant bubble. The "OpenAI is trusted" assumption is false: `gpt-4o` is user-steerable and will echo `<script>` or `<img onerror=…>` on request. This is exploitable today and becomes session-theft once auth/persistence land in Sprint 15. (Audit IF-2, 🔴 CRITICAL.)

**Exact Scope:**
- `chat_app/lib/chat_app/markdown.ex`:
  - Change `escape: false` to `escape: true` on the `Earmark.as_html/2` call.
  - Update the module's `@moduledoc` to remove the "trust boundary" wording. Replace with: `Converts Markdown to HTML, HTML-escaping any embedded raw HTML. Safe to render with Phoenix.HTML.raw/1 in HEEx templates because Earmark escapes < > & before parsing, while still emitting <code>/<pre> for fenced code blocks.`
- `chat_app/test/chat_app/markdown_test.exs`:
  - Replace the test `"trust boundary: raw HTML from AI output is passed through"` (~line 73–78) with a positive XSS-prevention test named `"raw HTML in input is HTML-escaped, not passed through"`:
    - Input: `"<script>alert('xss')</script>"`.
    - Assert: `refute result =~ "<script>"`.
    - Assert: `assert result =~ "&lt;script&gt;"` (or equivalent escaped form).
  - Add a complementary test `"fenced code blocks still render as <pre><code>"` that confirms `"```\nlet x = 1\n```"` still produces `<pre><code>` (no regression on code formatting).
- `chat_app/test/chat_app_web/live/chat_live_bubbles_test.exs`:
  - Replace the test `"XSS trust boundary: assistant content is rendered as raw HTML (trusted source)"` (~line 194–200) with `"XSS prevention: <script> in assistant content is HTML-escaped"`:
    - Use `send_and_finish/3` helper with `"<script>alert(1)</script>"` as the response.
    - Assert `refute html =~ "<script>"` and `assert html =~ "&lt;script&gt;"`.

**Acceptance Criteria:**
- [x] `markdown.ex` pre-escapes input HTML before Markdown rendering (option-2 implementation) and keeps `smartypants: false`.
- [x] `to_html("<script>alert(1)</script>")` returns a string containing `&lt;script&gt;` and NOT a literal `<script>`.
- [x] `to_html("\`code\`")` still produces `<code>` element.
- [x] `to_html("\`\`\`\nlet x=1\n\`\`\`")` still produces `<pre><code>`.
- [x] `to_html("**bold**")` still produces `<strong>bold</strong>` — bold/italic/list rendering unaffected.
- [x] All `markdown_test.exs` tests pass with the new assertions.
- [x] The new `chat_live_bubbles_test.exs` XSS-prevention test passes.
- [x] The `@moduledoc` no longer mentions "trusted server content" or "do NOT pass unfiltered user input".
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- Earmark's behavior on `&` in plain text — assert `"AT&T"` still renders as `AT&amp;T` (escaping is correct, not double-escaped).
- A model response containing literal Markdown that LOOKS like HTML (e.g. `` `<div>` `` inline code) — the inline-code path should still wrap the content in `<code>` and the angle brackets inside should be rendered as `&lt;` / `&gt;`.
- Mixed content: `"Hi **<b>bold</b>**"` — the `**` still produces `<strong>`, and the `<b>` tags inside become `&lt;b&gt;`.

**Do NOT do:**
- Do NOT add HtmlSanitizeEx or any allowlist-based sanitizer in this task — `escape: true` is sufficient for the threat model and avoids a new dep. (A future sprint may revisit if rich HTML embeds become a product requirement.)
- Do NOT remove the `raw/1` call in `chat_live.ex` — Earmark's output is now safe for `raw/1`.
- Do NOT change `smartypants: false`.

**Effort:** S
**Depends on:** None

---

### TASK 3 — Verify secrets posture: rotation + git-history scan + `.env.example` parity

**Context:**
The audit (Phase 4 #2 + IF-3) flags a live `sk-proj-…` OpenAI key currently in `chat_app/.env`. Even though `.env` is gitignored, the workspace is shared with humans and AI agents, and the key must be rotated AND the git history must be scanned to confirm the key was never committed. (Audit IF-3, 🔴 CRITICAL.)

**Exact Scope:**
- Run `git log --all --full-history -S "sk-proj-8qhYJ" -- .` from the `chat_app/` directory and capture the output. Document findings in this task's PR description and in `chat_app/CHANGELOG.md` under `[Unreleased] — Security`. Two outcomes:
  - **No matches** → mark this task complete, note "key never committed" in CHANGELOG.
  - **Matches** → STOP. Flag `🔴 BLOCKER: secret in git history` to the human and do NOT proceed; history rewrite (`git filter-repo`) requires explicit human approval.
- Confirm `.gitignore` at `chat_app/.gitignore` contains `.env` (already does — verify it is on a non-comment line).
- Confirm `.env.example` at `chat_app/.env.example` matches every key required by `config/runtime.exs` and `config/test.exs`. Required keys: `OPENAI_API_KEY`, `SECRET_KEY_BASE`, `PHX_SERVER`, `PHX_HOST`, `PORT`, `DNS_CLUSTER_QUERY`, `CHROMEDRIVER_PATH`, `CHROME_BINARY_PATH`. Verified by reading `.env.example` and grepping `runtime.exs` for `System.get_env`/`System.fetch_env!`. If any required key is missing from `.env.example`, ADD it with a placeholder.
- Add a one-paragraph note to `chat_app/README.md` under `## Environment variables` (after the table) titled `### Rotating the OpenAI key`. Three lines: revoke at https://platform.openai.com/api-keys, generate a new key, paste into local `.env` only — never commit.
- Update `chat_app/CHANGELOG.md` `[Unreleased] — Security` with: "Verified `.env` was never committed via `git log -S` scan (date: 2026-XX-XX). Rotated production OpenAI key as a precaution."

**Acceptance Criteria:**
- [x] `git log --all --full-history -S "sk-proj-" -- .` from `chat_app/` returns zero matches; the command output is pasted into the PR / completion notes.
- [x] `.env.example` contains every variable referenced by `System.get_env`/`System.fetch_env!` in `config/runtime.exs` plus the two test overrides.
- [x] `chat_app/.gitignore` contains `.env` on its own line (not commented).
- [x] `README.md` has a `### Rotating the OpenAI key` subsection with the three-step procedure.
- [x] `CHANGELOG.md` has a `### Security` entry under `[Unreleased]` documenting the scan and the rotation.
- [x] No application code or test was changed as part of TASK 3 scope.

**Edge Cases to Handle:**
- The scan command finds the key in a *deleted* file — still counts as a match; flag as blocker.
- `.env` exists but is missing a required variable — the dev-agent does NOT modify `.env` (that is the human's local file); only `.env.example` is touched.
- A future `.env.local` or `.env.test` file pattern — out of scope.

**Do NOT do:**
- Do NOT touch `chat_app/.env` — that is a developer's local file; the human rotates it, not the agent.
- Do NOT run `git filter-repo` or any history-rewrite command. If the scan finds matches, STOP and report.
- Do NOT commit any secret value, real or fake, into the repo.
- Do NOT change application code in this task.

**Effort:** S
**Depends on:** None

---

### TASK 4 — Make the OpenAI model configurable

**Context:**
`chat_app/lib/chat_app/openai.ex:19` hardcodes `model: "gpt-4o"`. This blocks the model picker (Sprint 16, F-4) and prevents per-environment tuning (e.g. `gpt-4o-mini` in test). It is the single most product-impactful constant in the codebase. (Audit IF-4, 🟠 MAJOR.)

**Exact Scope:**
- `chat_app/config/config.exs`: add `config :chat_app, :openai_model, "gpt-4o"` immediately after the `config :chat_app, generators: [...]` line.
- `chat_app/lib/chat_app/openai.ex`:
  - Add a private `defp openai_model, do: Application.get_env(:chat_app, :openai_model, "gpt-4o")` next to `defp api_url/0` and `defp api_key/0`.
  - Change line 19 from `model: "gpt-4o",` to `model: openai_model(),`.
- `chat_app/test/chat_app/openai_test.exs`: add a new test `"stream/2 sends the configured :openai_model in the request body"`:
  - Save the original via `Application.get_env/2`, set a unique value (e.g. `"gpt-test-12345"`).
  - Use `Req.Test.stub(ChatApp.OpenAI, fn conn -> ... end)` and inside the stub assert the request body's `"model"` field equals `"gpt-test-12345"`. Use `Plug.Conn.read_body/1` then `Jason.decode!/1`.
  - Send a 200 response with an empty `data: [DONE]\n\n` body so the call completes cleanly.
  - Restore the original via `on_exit/1`.

**Acceptance Criteria:**
- [x] `config/config.exs` defines `:openai_model` defaulting to `"gpt-4o"`.
- [x] `openai.ex` reads the model via `Application.get_env(:chat_app, :openai_model, "gpt-4o")` and contains zero string literals matching `"gpt-4o"` outside that default.
- [x] The new test passes and confirms `Application.put_env` overrides reach the outgoing HTTP body.
- [x] All existing OpenAI tests (`openai_test.exs`, `openai_integration_test.exs`) still pass with no changes.
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- A test that does NOT set `:openai_model` — the default `"gpt-4o"` is used (covered by existing integration tests that don't override).
- A `nil` value in app env (defensive) — `Application.get_env/3`'s default arg covers this.
- The model contains characters that need JSON escaping — Jason handles this; no custom logic needed.

**Do NOT do:**
- Do NOT add per-conversation model selection — that is F-4 in Sprint 16. This task only makes the model a single global config value.
- Do NOT add validation that the model exists at OpenAI — runtime errors are surfaced via `:stream_error` already.
- Do NOT change `:openai_model` per environment in `config/dev.exs` or `config/prod.exs` in this task.

**Effort:** S
**Depends on:** None

---

### TASK 5 — Fix invalid `<textarea value=...>` markup

**Context:**
`chat_app/lib/chat_app_web/live/chat_live.ex:205-215` renders `<textarea value={@input}>`. `value` is not a valid HTML attribute on `<textarea>`; the element only takes its content as the body. It "works" today because LiveView's client-side patcher writes `.value` after mount, but it breaks SSR (initial server-rendered HTML), accessibility tools, and view-source debugging. (Audit IF-7, 🟠 MAJOR.)

**Exact Scope:**
- `chat_app/lib/chat_app_web/live/chat_live.ex`:
  - Lines ~205-215: change the self-closing `<textarea ... value={@input} ... />` to a paired `<textarea ...>{@input}</textarea>`. Remove the `value={@input}` attribute. Move all other attributes (`id`, `name`, `phx-hook`, `rows`, `placeholder`, `class`, `style`, `disabled`) onto the opening tag. Inside the body, use HEEx interpolation `{@input}` (NOT `<%= @input %>`, since the parent tag does not have `phx-no-curly-interpolation` and a curly is not desired here — `@input` may contain literal `{` `}` from user typing, so use `<%= @input %>` instead — see edge cases below).
  - Final shape:
    ```heex
    <textarea
      id="chat-input"
      name="input"
      phx-hook="ChatComposer"
      rows="1"
      placeholder="Ask..."
      class="flex-1 resize-none bg-transparent px-[--chat-composer-field-padding-inline] py-[--chat-composer-field-padding-block] text-sm outline-none"
      style="max-height: 192px; overflow-y: hidden;"
      disabled={@is_sending}
    ><%= @input %></textarea>
    ```
- `chat_app/test/chat_app_web/live/chat_live_events_test.exs`:
  - The existing test `"send_message clears the input field"` (~line 28-38) currently asserts `html =~ ~r/<textarea[^>]+value=""/`. Replace with an assertion that the textarea's body is empty. Two acceptable approaches:
    - Floki: parse the HTML, find the textarea, assert `Floki.text/1` of the matched node is `""` after trim.
    - Regex on body: `assert html =~ ~r/<textarea[^>]*>(\s*)<\/textarea>/`.
  - Choose Floki for clarity.
- `chat_app/test/chat_app_web/live/chat_live_test.exs`: any regex relying on `value=""` on the textarea (none currently exist — verify by ripgrep before merge) must be updated similarly.

**Acceptance Criteria:**
- [x] No occurrence of `value={@input}` or `value="..."` on any `<textarea>` element in the codebase (verified by `rg 'textarea[^>]*value=' lib/`).
- [x] The textarea is rendered as a paired `<textarea>...</textarea>` with the input content inside the body.
- [x] When `@input` is empty, the rendered HTML body of the textarea is empty (no whitespace beyond the HEEx interpolation expansion).
- [x] When the user types `"hello {world}"`, both literal `{` and `}` round-trip into the textarea body without HEEx parse errors.
- [x] All existing LiveView tests pass after assertion updates.
- [ ] `mix precommit` exits 0.

**Edge Cases to Handle:**
- User input contains literal `{` or `}` — `<%= @input %>` is the safe form because HEEx curly interpolation `{...}` would conflict with literal braces. Verify by typing `let x = {a: 1}` into the composer in dev and confirming no template error.
- User input contains `&`, `<`, `>` — Phoenix.HTML auto-escapes when interpolated via `<%= %>`; verify with a test typing `"<b>foo</b>"` and asserting the rendered textarea body contains `&lt;b&gt;`.
- Multi-line input (`\n` characters) — the textarea body should preserve them; the `ChatComposer` hook's `resize/0` already handles reflow.

**Do NOT do:**
- Do NOT change the `phx-change="update_input"` or `phx-submit="send_message"` form behaviors.
- Do NOT change `ChatComposer.js` — the hook reads `el.value`, which the browser still populates correctly from the textarea body.
- Do NOT remove the `disabled={@is_sending}` attribute.
- Do NOT add `phx-no-curly-interpolation` to the textarea (the chosen `<%= @input %>` form does not need it).

**Effort:** S
**Depends on:** None

---

## DEFERRED TO SPRINT 12

- **IF-5 Rate limiting (Hammer):** depends on IF-8's pid storage to track per-session usage cleanly; sequenced into Sprint 12 with the other `chat_live.ex` mutations.
- **IF-6 Errors split out of `messages`:** touches `chat_live.ex` in the same region as IF-8; sequenced after IF-8 in Sprint 12 to avoid merge churn.
- **IF-8 Task.Supervisor + cancellation:** touches the same `send_message` block; lands first in Sprint 12 and is the prerequisite for IF-5 and IF-6.
- **IF-9 Delete orphaned scaffold:** moves last in Sprint 12; requires the rest of `chat_live.ex` to be in its target shape so `compile --warnings-as-errors` is clean after each deletion.

## SPRINT RISKS

- **Earmark `escape: true` regression on existing fixture content:** if the team has demo prompts that rely on raw HTML in assistant output, they will now render as escaped text. Mitigation: the integration test suite has no such fixtures; verified by reading `openai_integration_test.exs` (only emits `"Hello"`, `" world"`, etc.).
- **Test-env coupling on `:allow_hero_override`:** if a downstream test in `async: true` mode reads the flag before `config/test.exs` is loaded, it could see `false`. Mitigation: the flag is set at `config/test.exs` load time (compile-time), not in `setup`, so it is available before any test runs.
- **Git-history scan in TASK 3 finds the key:** would block the sprint and require human-driven `git filter-repo`. Mitigation: the audit notes the key is in `.env` (gitignored) — the scan is precautionary, not expected to find anything.
- **Dotenvy in dev startup interaction with new `:openai_model` config:** none — `:openai_model` is set in `config/config.exs` (compile-time), not via env var.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:
- [x] All five tasks pass their acceptance criteria.
- [ ] `mix precommit` exits 0 (compile --warnings-as-errors + format + test). _Blocked by pre-existing `core_components.ex` formatter drift and stale `mix.lock` entries — both flagged as out-of-scope known gaps in CHANGELOG._
- [x] `cd assets && npm test` exits 0. _16 vitest specs pass._
- [x] No new 🔴 CRITICAL or 🟠 MAJOR issues introduced (verified by re-running the audit checklist on the affected files).
- [x] `CHANGELOG.md` `[Unreleased]` section is updated with the Security note from TASK 3 and a `### Fixed` block summarizing the four code changes.
- [x] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict
SHIP WITH FIXES — sprint code is correct and all 174 non-E2E tests are green. Two pre-existing repo-level blockers (Wallaby E2E session failures, `core_components.ex` formatter drift) prevent `mix precommit` from exiting 0 but are outside Sprint 11 scope.

## Completion Notes
- Implemented TASK 1–5 in order with focused validation after each task.
- TASK 2 used option-2 hardening: pre-escape input HTML before Markdown parsing, because `Earmark.as_html(..., escape: true)` did not escape raw `<script>` blocks in this environment.
- `git log --all --full-history -S "sk-proj-" -- .` returned no matches (clean history scan result).
- One pre-existing LiveView bubble width regression was fixed by adding `max-w-[80%]` to user bubbles.

### QA findings (post-implementation review)

| Sev | Finding | Resolution |
| --- | --- | --- |
| MAJOR | TASK 1 prescribed regression test was placed only in `test/integration/sprint_11_immediate_fixes_correctness_test.exs`, not in `chat_live_test.exs` as the sprint scope required. | Added `"hero_state defaults to true regardless of params when allow_hero_override is false"` to `test/chat_app_web/live/chat_live_test.exs` and converted that file to `async: false` (Application env mutation is not safe under `async: true`). All 49 tests in the file still pass. |
| MINOR | `chat_app/.env.example` comment described the model as "hardcoded in lib/chat_app/openai.ex". | Updated the comment to point at the new `:openai_model` config key with the `"gpt-4o"` default. |
| MINOR | Earmark link URLs containing `&` get pre-escaped to `&amp;` before parsing, so `[link](http://x?a=1&b=2)` renders `<a href="http://x?a=1&amp;b=2">`. Browsers decode the entity correctly, so this is functionally correct but worth noting if a future test asserts raw URL content. | No code change. Noted here for Sprint 12. |
| MINOR (pre-existing) | `mix format --check-formatted` fails on `lib/chat_app_web/components/core_components.ex` (the orphaned dead-code file flagged in the CHANGELOG known gaps). | Out of Sprint 11 scope; tracked in `[Unreleased] Known gaps`. |
| MINOR (pre-existing) | `mix deps.unlock --unused` reports stale entries (`bandit`, `cc_precompiler`, `elixir_make`, `fine`, `heroicons`, `lazy_html`, `thousand_island`). | Out of Sprint 11 scope; should be cleaned in a Sprint 12 housekeeping task. |
| MINOR (env) | All Wallaby E2E tests (existing baseline + sprint additions) fail with `invalid session id`. | Confirmed environmental — affects baseline tests that pre-date this sprint. No Sprint 11 code change needed. |

### Verified after QA fixes
- `mix test --exclude e2e --exclude real_api` → 174 passed, 0 failed, 1 skipped.
- `MIX_ENV=prod mix compile --warnings-as-errors` → 0 warnings.
- `cd assets && npm test` → 16 passed.
- `rg "Mix\\." chat_app/lib/` → 0 matches.
- `rg '"gpt-4o"' chat_app/lib/` → 1 match (the `Application.get_env/3` default in `openai.ex`).
- `rg 'textarea[^>]*value=' chat_app/lib/` → 0 matches.
- `git log --all --full-history -S "sk-proj-" -- chat_app` → 0 matches.
