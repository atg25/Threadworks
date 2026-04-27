---
status: complete
activated: Apr-26-2026
completed: Apr-26-2026
---

# SPRINT 14 — Hardening B: Tooling, Docs & Governance

**Status:** COMPLETE
**Created:** 2026-04-24
**Activated:** 2026-04-26
**Completed:** 2026-04-26

## Goal

Close the remaining hardening backlog (H-8 through H-12): wire Vitest into `mix precommit`, document the web modules, drop unused config noise, ship a CI pipeline that enforces tests on every PR, and land a LICENSE file so the repo is no longer an ambiguity blocker for any third party.

**Total effort:** ~5 hours (1 × M + 4 × S)
**Parallelizable:** All five tasks are fully independent. They can run in parallel branches.

---

## TDD Test Specification

This sprint is mostly tooling, docs, and governance — most of its acceptance is validated by static checks and CI assertions, not unit/integration tests of new logic. The following layered tests verify the behavior change that _is_ observable. Per-task tests inside each TASK block remain the source of truth for shape; this section is additive.

### Layer summary

| Layer       | Tool                                                                                     | Test files                                                                        | Tasks               |
| ----------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------- |
| Unit        | ExUnit                                                                                   | `test/chat_app_web/router_pipeline_test.exs` (new — verifies pipeline list shape) | 3                   |
| Integration | `Phoenix.ConnTest`, `Phoenix.LiveViewTest`                                               | `test/chat_app_web/router_test.exs` (new)                                         | 3                   |
| E2E         | Wallaby + ChromeDriver (`@moduletag :e2e`, deferred from CI in TASK 4)                   | `test/chat_app_web/features/chat_e2e_test.exs`                                    | 4 (manual smoke), 5 |
| Static      | ripgrep, `mix compile --warnings-as-errors`, `mix docs`, `mix precommit`, `gh pr checks` | CI step / PR description                                                          | 1, 2, 3, 4, 5       |

### Unit tests

| Test name                                      | Inputs                                                                                                        | Expected                                                                                          | Guards against                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `Router pipelines list contains :browser only` | `ChatAppWeb.Router.__pipelines__/0` (or `Router.__routes__/0` filtered for the root scope's `:pipe_through`). | The pipelines exposed are exactly `[:browser]` (until Sprint 15 TASK 3 introduces `:basic_auth`). | TASK 3 — accidental re-introduction of `:api`. |
| `Router has a non-stale @moduledoc`            | `Code.fetch_docs(ChatAppWeb.Router)`.                                                                         | `@moduledoc` is a binary, length > 100 chars, contains `"single browser pipeline"`.               | TASK 2 — silent revert to scaffold default.    |
| `Endpoint has a non-stale @moduledoc`          | `Code.fetch_docs(ChatAppWeb.Endpoint)`.                                                                       | `@moduledoc` is a binary, contains `"SECRET_KEY_BASE"`.                                           | TASK 2 — scaffold drift.                       |

### Integration tests

| Test name                                                | Inputs                                                                  | Expected                                                                 | Guards against                                                   |
| -------------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `GET / still returns 200 after pipeline cleanup`         | `get(conn, "/")` post-TASK 3.                                           | Status 200; HTML contains the chat composer textarea.                    | TASK 3 — over-aggressive deletion taking down the chat scope.    |
| `GET /api/* returns 404 (no api scope wired)`            | `get(conn, "/api/anything")`.                                           | `assert_error_sent 404`.                                                 | TASK 3 — undocumented re-add of `:api` scope.                    |
| `mix docs runs without warnings on the five web modules` | Shell-out from a test or Make task: `mix docs 2>&1` after TASK 2 lands. | Exit 0; stderr contains zero `warning:` lines for the five module names. | TASK 2 — malformed `@moduledoc` heredocs producing invalid HTML. |

### E2E tests (Wallaby — local only; not run in CI per TASK 4 design)

| Test name                                                                                                       | Inputs                                                                                                                  | Expected                                                                                                                      | Guards against                                                                                   |
| --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Positive — full happy-path smoke after CI lands                                                                 | Run the existing `chat_e2e_test.exs` `@moduletag :e2e` suite locally with `mix test --only e2e` after a CI green build. | Suite exits 0; `data-chat-state="ready"` reaches `data-chat-state="streaming"` then back; assistant bubble has rendered text. | TASK 4 — silent breakage of the E2E suite while only `--exclude e2e` is enforced in CI.          |
| Negative — running `mix precommit` with a deliberately broken Vitest test fails the alias                       | Edit one Vitest test to `expect(true).toBe(false)`; run `mix precommit`.                                                | Alias exits non-zero; output contains `"vitest"` and the failing test name. Revert the change.                                | TASK 1 — Vitest stage silently no-op'd because `cmd --cd assets npm test` swallowed the failure. |
| Negative — fresh clone bootstrap without `cd assets && npm install` fails the new step with an actionable error | On a CI image with no `node_modules`, run `mix precommit`.                                                              | Step fails with stderr mentioning `vitest: command not found` (or equivalent); README has a one-line fix.                     | TASK 1 — undocumented dependency on `npm install` blocking new contributors.                     |

### Static / CI checks (no test framework)

| Check                                               | Inputs                                                                                                                                                 | Expected                                                                                                                                   | Guards against                                             |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| `precommit` alias contains all five steps in order  | `rg "precommit:" chat_app/mix.exs -A 8`                                                                                                                | Output lists `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`, `cmd --cd assets npm test` in that order.           | TASK 1 — reorder breaks fast-fail expectations.            |
| `:api` pipeline absent from router                  | `rg "pipeline :api" chat_app/lib/chat_app_web/router.ex`                                                                                               | Zero matches.                                                                                                                              | TASK 3 regression.                                         |
| Five web modules have non-stale `@moduledoc`        | `rg "@moduledoc \\\"\\\"\\\"" chat_app/lib/chat_app_web/{live/chat_live.ex,router.ex,endpoint.ex,components/layouts.ex,components/core_components.ex}` | Five matches; none equal the original `phx.new` default ("This module holds layouts and related functionality used by your application."). | TASK 2 — partial completion.                               |
| `.github/workflows/ci.yml` exists at repo root      | `test -f .github/workflows/ci.yml && echo OK`                                                                                                          | `OK`.                                                                                                                                      | TASK 4 — workflow committed inside `chat_app/` by mistake. |
| CI workflow runs the documented suites              | `rg "mix test --exclude real_api --exclude e2e" .github/workflows/ci.yml`                                                                              | Exactly one match.                                                                                                                         | TASK 4 — accidental exclusion drift.                       |
| `gh pr checks` passes for an opened PR              | Open a no-op PR; run `gh pr checks <pr>`.                                                                                                              | All checks `pass`; total time < 15 min.                                                                                                    | TASK 4 — workflow installed but consistently red.          |
| `chat_app/LICENSE` exists with SPDX-conformant text | `head -3 chat_app/LICENSE`                                                                                                                             | First line is `MIT License` (or chosen SPDX header); body matches the canonical text.                                                      | TASK 5 — empty / stub license.                             |
| `mix.exs` has `package` block with `licenses:`      | `rg "licenses: \\[" chat_app/mix.exs`                                                                                                                  | Exactly one match.                                                                                                                         | TASK 5 — Hex publish gating absent.                        |
| README's License section points to LICENSE file     | `rg "\\[MIT License\\]\\(LICENSE\\)" chat_app/README.md` (or chosen)                                                                                   | Exactly one match.                                                                                                                         | TASK 5 — stale "Treat as proprietary" text remains.        |

---

## Tasks

### TASK 1 — Wire Vitest into `mix precommit` and verify Vite/Vitest setup is complete

**Context:**
The audit's H-8 says "decide on Vite+Vitest or remove it." Inspection shows `assets/vite.config.js`, `assets/vitest.config.js`, and `assets/test/hooks/*.test.js` already exist and pass. The remaining gap is that `mix precommit` (in `chat_app/mix.exs:78`) does NOT run Vitest, so the JS hook tests can silently regress on commit. (Audit H-8, 🟡 MINOR.)

**Exact Scope:**

- `chat_app/mix.exs`:
  - Update the `precommit` alias from:
    ```elixir
    precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ```
    to:
    ```elixir
    precommit: [
      "compile --warnings-as-errors",
      "deps.unlock --unused",
      "format",
      "test",
      "cmd --cd assets npm test"
    ]
    ```
  - The `cmd` Mix task runs an arbitrary shell command; the `--cd` flag changes directory. This is the same pattern Phoenix's `assets.deploy` alias uses.
- Verify `chat_app/assets/package.json` has `"test": "vitest run"` (it does — line 3). No change needed.
- Verify `chat_app/assets/vitest.config.js` has `environment: "jsdom"` (it does). No change needed.
- Verify all existing Vitest tests pass: `cd chat_app/assets && npm test`. If any pre-existing test fails, fix it inline (likely a CI environment expectation mismatch — out of scope to add new tests here).
- `chat_app/README.md`:
  - Update the "Tests" section to note that `mix precommit` now also runs Vitest. Add: `mix precommit` runs the full Elixir suite plus the Vitest JS hook suite. Replace the standalone `cd assets && npm test` line in that section with: `Run the JS hook tests directly via cd assets && npm test, or as part of mix precommit.`

**Acceptance Criteria:**

- [ ] `mix precommit` invokes Vitest as its final step.
- [ ] `mix precommit` exits 0 on a clean checkout.
- [ ] If a Vitest test fails, `mix precommit` exits non-zero (verified by temporarily breaking a test and reverting).
- [ ] `chat_app/README.md` documents the integration.
- [ ] No additional dependencies were added to `mix.exs` or `package.json`.
- [ ] Adding any new ChatScroll/ChatComposer test in `assets/test/hooks/` is automatically covered by the next `mix precommit` run.

**Edge Cases to Handle:**

- `npm` is not on `PATH` (rare; CI runners install Node + npm) — `cmd --cd assets npm test` will fail with a useful error. Acceptable: README's prerequisites already require Node 20+.
- Vitest cache permissions on a fresh CI image — `vitest run` is the non-watch mode and does not write to a cache that requires permissions. Verified.
- Running `mix precommit` while `vite` watch is also running locally — `vitest run` is independent of the Vite dev server. No interaction.

**Do NOT do:**

- Do NOT replace ESBuild with Vite as the production bundler in this task — `assets.deploy` still uses ESBuild. The Vite plugin in `vite.config.js` is purely for Tailwind v4 plugin support during testing.
- Do NOT add new Vitest tests in this task; only wire what exists.
- Do NOT pin a specific Vitest version higher than `package.json` already specifies.

**Effort:** S
**Depends on:** None.

---

### TASK 2 — Add `@moduledoc` to remaining web modules

**Context:**
`ChatAppWeb.ChatLive`, `ChatAppWeb.Router`, `ChatAppWeb.Endpoint`, `ChatAppWeb.Layouts`, and `ChatAppWeb.CoreComponents` (after Sprint 12 trim) have either no `@moduledoc` or a stale Phoenix-scaffold-generated one. New engineers cannot orient quickly. (Audit H-9, 🟡 MINOR.)

**Exact Scope:**

For each of the five modules below, add or replace the `@moduledoc` with one paragraph (3-6 sentences) that names: (a) what the module is, (b) what it owns, (c) any non-obvious decision worth knowing.

- `chat_app/lib/chat_app_web/live/chat_live.ex`: ADD `@moduledoc` immediately after `defmodule ... do`. Suggested content:

  ```
  @moduledoc """
  The single LiveView at "/" — owns the chat state machine: composer input,
  is_sending flag, streamed assistant buffer, message list, and per-session
  rate-limit key.

  Uses `Phoenix.LiveView` directly (not `ChatAppWeb, :live_view`) so we can
  pass `container: {:div, style: "height: 100%;"}` — the wrapping div must
  carry `height: 100%` to propagate the body's height down to the inner
  <section>; without it, `h-full` on the section resolves to 0.

  The streaming task is supervised under `ChatApp.TaskSupervisor` and its
  pid is held in `assigns.stream_task_pid` so `terminate/2` can kill it on
  LiveView teardown.
  """
  ```

  (Update the third paragraph if any of TASKS 12.1 / 12.3 land differently than expected.)

- `chat_app/lib/chat_app_web/router.ex`: ADD `@moduledoc`:

  ```
  @moduledoc """
  Single browser pipeline serving one route — `live "/", ChatLive, :index`.
  No `:api` scope is wired today. The `:browser` pipeline includes session
  fetch, CSRF protection, and secure-headers — all required for LiveView.
  """
  ```

- `chat_app/lib/chat_app_web/endpoint.ex`: REPLACE any existing `@moduledoc` with:

  ```
  @moduledoc """
  Phoenix endpoint for ChatAppWeb. Standard configuration: session cookie
  signed with SECRET_KEY_BASE, LiveView socket at /live, Phoenix CodeReloader
  in dev only. The endpoint is the topmost child of the application supervisor.
  """
  ```

- `chat_app/lib/chat_app_web/components/layouts.ex`: REPLACE the stale "This module holds layouts and related functionality used by your application." with:

  ```
  @moduledoc """
  Application layouts and the flash-group component. Hosts:

    * `app/1`           — the root layout slot wrapper (currently a thin <main>).
    * `flash_group/1`   — renders :info / :error / phx-disconnected / phx-server-error toasts.

  The `<.flash>` and `<.icon>` primitives are imported from
  `ChatAppWeb.CoreComponents`.
  """
  ```

- `chat_app/lib/chat_app_web/components/core_components.ex`: REPLACE the long daisyUI-referencing `@moduledoc` (current lines 2-28) with:

  ```
  @moduledoc """
  The minimum set of UI primitives this app actually uses:

    * `flash/1` and `flash_group/1` for connection-status and server-error toasts.
    * `icon/1` for Heroicons (used by flash and by error pages).
    * `show/2` and `hide/2` JS commands.
    * `translate_error/1` and `translate_errors/2` for gettext error formatting.

  daisyUI is NOT a dependency. The chat surface uses `assets/css/chat.css`
  custom classes (`.ui-chat-*`); flash toasts use Tailwind utility classes
  inline.
  """
  ```

**Acceptance Criteria:**

- [ ] Each of the five modules has the documented `@moduledoc` above.
- [ ] `mix compile --warnings-as-errors` exits 0.
- [ ] Running `mix docs` (after adding `:ex_doc`, dev-only — see below) generates HTML for all five modules without warnings.
  - If `ex_doc` is not yet in `mix.exs`, ADD it as `{:ex_doc, "~> 0.31", only: :dev, runtime: false}` and run `mix deps.get`. The `mix docs` invocation is the verification gate; the published artifact is not required.
- [ ] No behavior changes (these are docstring-only edits).

**Edge Cases to Handle:**

- `Endpoint`, `Router`, `Layouts`, `CoreComponents` are partially generated by `phx.new` — preserve any non-`@moduledoc` content verbatim. Only the docstring changes.
- `ChatLive`'s existing `# Use Phoenix.LiveView directly...` comment block (lines 2-15) duplicates information now in `@moduledoc`. DELETE that comment block; the `@moduledoc` supersedes it.

**Do NOT do:**

- Do NOT add `@doc` to private functions in this task.
- Do NOT add docstrings to test modules.
- Do NOT add `@moduledoc false` anywhere — every public web module gets a real docstring.
- Do NOT rewrite the `@moduledoc`s on `ChatApp.OpenAI`, `ChatApp.OpenAI.SSE`, `ChatApp.Markdown`, `ChatApp.Chat`, `ChatApp.OpenAI.Stub`, `ChatApp.OpenAI.E2EStub` — they are already adequate.

**Effort:** S
**Depends on:** Sprint 12 TASK 1 (the third paragraph of `ChatLive`'s docstring references `TaskSupervisor`; if Sprint 12 has not landed, omit that paragraph).

---

### TASK 3 — Drop the unused `:api` pipeline and the `generators:` config

**Context:**
`chat_app/lib/chat_app_web/router.ex:13-15` defines a `:api` pipeline that is never piped into a scope (the only `scope` is `"/"` with `:browser`). `chat_app/config/config.exs:10-11` sets `generators: [timestamp_type: :utc_datetime]` which is not used because no Ecto generators run in this app yet. Both are scaffold leftovers that signal "this matters" to new engineers when it doesn't. (Audit H-10, 🟡 MINOR.)

**Exact Scope:**

- `chat_app/lib/chat_app_web/router.ex`:
  - Delete lines 13-15 (the `pipeline :api do ... end` block).
  - Delete the trailing comment block (lines 23-26 — the commented-out `# scope "/api", ChatAppWeb do ... end`).
- `chat_app/config/config.exs`:
  - DECISION: Sprint 15 will add Ecto and use this config. Do NOT delete the line; instead, ADD a comment above it: `# Used by Ecto generators (mix phx.gen.schema, etc.) once Sprint 15's persistence layer lands.`
  - If the dev agent disagrees and prefers to delete: deletion is acceptable, since Sprint 15 explicitly lists "add the generators line back" as part of its TASK 1 setup. Annotate the choice in the sprint completion notes.

**Acceptance Criteria:**

- [ ] `chat_app/lib/chat_app_web/router.ex` has no `:api` pipeline and no commented-out `:api` scope.
- [ ] `chat_app/config/config.exs:10-11` either has the explanatory comment OR has been deleted (the choice is documented in Sprint 14 completion notes).
- [ ] `mix compile --warnings-as-errors` exits 0.
- [ ] `mix test` exits 0.

**Edge Cases to Handle:**

- A future scope adds `pipe_through :api` — that scope's author re-adds the pipeline. No risk.
- Removing the `:api` pipeline does not break `error_json.ex` — `ErrorJSON` is invoked by the endpoint's `render_errors:` config, not via the router pipeline.

**Do NOT do:**

- Do NOT delete `chat_app/lib/chat_app_web/controllers/error_json.ex`.
- Do NOT delete the `formats: [html: ChatAppWeb.ErrorHTML, json: ChatAppWeb.ErrorJSON]` config in `config.exs:17`.
- Do NOT modify any other line in `router.ex`.

**Effort:** S
**Depends on:** None.

---

### TASK 4 — Add a minimal CI config

**Context:**
Tests exist (~80+ across ExUnit, LiveView, integration, E2E, Vitest) but nothing runs them on PR. A regression that breaks the suite can land on `main`. (Audit H-11, 🟡 MINOR.)

**Exact Scope:**

Create `.github/workflows/ci.yml` at the **repo root** (NOT inside `chat_app/`). The workflow file:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-22.04
    timeout-minutes: 15
    defaults:
      run:
        working-directory: chat_app

    env:
      MIX_ENV: test
      OPENAI_API_KEY: sk-test-stub-ci

    steps:
      - uses: actions/checkout@v4

      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.15.7"
          otp-version: "26.2"

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: |
            chat_app/deps
            chat_app/_build
          key: mix-${{ runner.os }}-${{ hashFiles('chat_app/mix.lock') }}
          restore-keys: mix-${{ runner.os }}-

      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix test --exclude real_api --exclude e2e

      - uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Cache npm
        uses: actions/cache@v4
        with:
          path: chat_app/assets/node_modules
          key: npm-${{ runner.os }}-${{ hashFiles('chat_app/assets/package.json') }}

      - run: npm install
        working-directory: chat_app/assets
      - run: npm test
        working-directory: chat_app/assets
```

Notes:

- `--exclude e2e` skips Wallaby in CI for v1. The Wallaby tests use `@moduletag :e2e` (verified in `chat_e2e_test.exs:100`). Adding Chrome to CI is deferred to a future sprint when Wallaby coverage proves valuable enough to justify the runtime.
- The `OPENAI_API_KEY` env var is set to a stub value; CI never makes a real OpenAI call because tests use `:openai_module` overrides.
- Pin `elixir-version: "1.15.7"` and `otp-version: "26.2"` to match the dev shop's `~> 1.15` requirement.

Update `chat_app/README.md`:

- Add a "CI" subsection under "Tests" with one paragraph explaining what runs on every PR.
- Add a status badge near the top of the README: `![CI](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg)`. Use a placeholder `<owner>/<repo>` and document in completion notes that the human must replace it after the first push to GitHub.

**Acceptance Criteria:**

- [ ] `.github/workflows/ci.yml` exists at the repo root.
- [ ] On a PR, the workflow runs `mix deps.get`, `mix compile --warnings-as-errors`, `mix test --exclude real_api --exclude e2e`, `npm install`, `npm test`.
- [ ] Caches for `_build`, `deps`, and `node_modules` are configured.
- [ ] On a fresh PR with passing tests, all CI steps exit 0 within 15 minutes.
- [ ] On a PR that breaks any test, the corresponding CI step exits non-zero and the PR is marked failing.
- [ ] `README.md` has a CI section explaining what runs.

**Edge Cases to Handle:**

- Someone runs `mix precommit` locally (which now includes Vitest from TASK 1) — CI's separate Elixir + Node steps cover the same ground; no double-spend.
- A PR that only changes `docs/` — workflow still runs but is fast (cache hits + zero recompile).
- `puppeteer` deps in `chat_app/assets/node_modules` — only `tailwindcss`, `vite`, `vitest`, etc. are in `package.json`; no Chrome download in CI.
- Cache miss on first run — workflow takes ~5-8 minutes; subsequent runs ~2 minutes.

**Do NOT do:**

- Do NOT run Wallaby E2E tests in CI. Add them in a follow-up after a containerized Chrome image is selected.
- Do NOT add `mix dialyzer` or `mix credo` checks — neither dep is installed; introducing them is a separate decision.
- Do NOT add deployment / release steps. CI is test-only.
- Do NOT add a real `OPENAI_API_KEY` secret to GitHub.
- Do NOT add a CodeQL or other security scanner — out of scope.

**Effort:** M
**Depends on:** TASK 1 (the alias change is upstream of the CI npm-test step).

---

### TASK 5 — Seed a LICENSE file

**Context:**
README.md currently says "Not specified. Treat as proprietary until the owner adds a LICENSE file." That is a hard blocker for any third-party use, contribution, or open-sourcing. (Audit H-12, 🟡 MINOR; also flagged in REQUIRES HUMAN INPUT #1.)

**Exact Scope:**

This task has a human-input dependency: the team must decide MIT / Apache-2.0 / proprietary. If the dev agent runs without explicit human input, default to MIT (the common choice for solo / small-team Phoenix apps). Document the choice in the PR description and ask for confirmation before merging.

If MIT is chosen:

- Create `chat_app/LICENSE` at the chat_app root with the standard SPDX-tagged MIT text. Use the exact format from https://opensource.org/license/mit/. Year: `2025-2026`. Copyright holder: ask the human for the canonical name; if blank, use `ChatApp Contributors`.
- `chat_app/mix.exs`: add a `package` metadata block to `project/0`:
  ```elixir
  package: [
    licenses: ["MIT"],
    links: %{"GitHub" => "https://github.com/<owner>/<repo>"}
  ],
  description: "A single-page streaming AI chat console built on Phoenix LiveView."
  ```
  Both fields are required for any future `mix hex.publish`.

If Apache-2.0 is chosen:

- Create `chat_app/LICENSE` with the full Apache 2.0 text from https://www.apache.org/licenses/LICENSE-2.0.txt.
- `mix.exs`: same `package` block but `licenses: ["Apache-2.0"]`.

If proprietary:

- Create `chat_app/LICENSE` with a one-paragraph "All Rights Reserved" notice naming the copyright holder and year.
- `mix.exs`: `licenses: ["LicenseRef-Proprietary"]` (SPDX user-defined identifier).

Update `chat_app/README.md`:

- Replace the entire "License" section (currently lines 215-217) with: `This project is released under the [MIT License](LICENSE).` (or whichever was chosen).

Update `chat_app/CHANGELOG.md`:

- Add an entry under `[Unreleased] — Added`: `LICENSE file (MIT) and SPDX licenses metadata in mix.exs.` (or whichever was chosen).

**Acceptance Criteria:**

- [ ] `chat_app/LICENSE` exists with valid SPDX-conformant text.
- [ ] `chat_app/mix.exs` has a `package` block with `licenses: [...]`.
- [ ] `chat_app/README.md`'s License section points to `LICENSE`.
- [ ] `chat_app/CHANGELOG.md` documents the addition.
- [ ] `mix compile --warnings-as-errors` exits 0 (the `package` field does not break compilation).
- [ ] The PR description explicitly names the chosen license and the copyright holder.

**Edge Cases to Handle:**

- Multiple copyright holders (e.g. solo dev + employer) — list all on the LICENSE line, comma-separated. Ask the human if uncertain.
- The repo includes vendored code (`chat_app/assets/vendor/`) — verify each vendored file has a header license; if not, document them in a `THIRD_PARTY_LICENSES.md` (out of scope for v1; flag if found).

**Do NOT do:**

- Do NOT publish to Hex.pm in this task.
- Do NOT change Phoenix's bundled fonts / images (none exist; `priv/static/` only has compiled assets).
- Do NOT add a CONTRIBUTING.md or CODE_OF_CONDUCT.md in this task — separate decisions.
- Do NOT default to GPL or AGPL without explicit human approval.

**Effort:** S (with human input on choice) / M (if the human input is hard to get and the team chooses to escalate)
**Depends on:** Human input on license choice — flag as `🟡 NEEDS CLARIFICATION` in the PR if unanswered.

---

## DEFERRED TO SPRINT 15

- **F-1 Conversation persistence (Ecto + SQLite):** the largest single feature in the audit; gets its own sprint with prerequisites resolved.
- **F-2 Basic auth / allowlist:** depends on rate-limit (Sprint 12) and persistence semantics (Sprint 15 TASK 1).
- **F-5 Stop / regenerate controls:** depends on `Task.Supervisor` from Sprint 12 TASK 1; lands as the first user-visible feature on the new platform.
- **F-7 Theme-toggle UI:** independent but small; bundled with the rest of the UX in Sprint 15 / 16.

## SPRINT RISKS

- **CI cache key churn** (TASK 4): `hashFiles('chat_app/mix.lock')` invalidates the cache on every dep change; first run after a Sprint 15 Ecto add is a full compile. Acceptable.
- **License ambiguity** (TASK 5): if the human is silent, the dev agent's default-to-MIT may not match institutional policy. Mitigation: PR description must explicitly call out the choice.
- **Vitest in `mix precommit`** (TASK 1) **fails on missing node_modules**: the first run after a fresh checkout will fail until `cd assets && npm install` runs once. Mitigation: README's setup section should mention this. Add to README in this sprint.
- **`generators:` deletion vs Sprint 15 add-back** (TASK 3): keeping the comment is the safer default; the choice is documented in completion notes.

## DEFINITION OF DONE — SPRINT COMPLETE WHEN:

- [ ] All five tasks pass their acceptance criteria.
- [ ] `mix precommit` exits 0 and includes `cd assets && npm test` as its final step.
- [ ] `.github/workflows/ci.yml` is on a PR and shows green.
- [ ] `chat_app/LICENSE` exists.
- [ ] All five web modules have non-stale `@moduledoc`s.
- [ ] `:api` pipeline is gone.
- [ ] `CHANGELOG.md` `[Unreleased]` documents this sprint's additions.
- [ ] QA audit prompt has been run and verdict is SHIP or SHIP WITH FIXES.

---

## QA Verdict

TBD

## Completion Notes

TBD
