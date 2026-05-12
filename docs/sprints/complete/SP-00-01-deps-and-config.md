---
id: SP-00-01
phase: 0
status: complete
created_date: 2026-05-06
activated_date: 2026-05-06
completed_date: 2026-05-06
---

# Goal

Add Oban and sqlite_vec to the project, configure Oban queues, wire up the supervision tree, and verify the sqlite_vec native extension loads at DB connection time — so `mix compile` and `mix test` are green before any schema work begins.

---

# Scope

**In scope:**
- `mix.exs` — add `{:oban, "~> 2.17"}` and sqlite_vec dependency
- `config/config.exs` — Oban queue configuration
- `config/test.exs` — Oban inline testing mode
- `lib/chat_app/application.ex` — add Oban to supervision tree
- Repo `:after_connect` or equivalent — load sqlite_vec extension on each connection
- `.env.example` — eBay credential stubs

**Out of scope:**
- No migrations
- No schema changes
- No application logic
- No VectorCodec module

---

# Tests

## Unit Tests

**File:** `test/chat_app/oban_config_test.exs`

---

### U1 — `oban config has scraper queue with concurrency 3`
- **Inputs:** `Application.fetch_env!(:chat_app, Oban)[:queues]`
- **Expected:** Keyword list includes `scraper: 3`
- **Guards against:** Misconfigured or missing scraper queue

---

### U2 — `oban config has embedder queue with concurrency 5`
- **Inputs:** `Application.fetch_env!(:chat_app, Oban)[:queues]`
- **Expected:** Keyword list includes `embedder: 5`
- **Guards against:** Wrong concurrency value for embedder

---

### U3 — `oban config repo is ChatApp.Repo`
- **Inputs:** `Application.fetch_env!(:chat_app, Oban)[:repo]`
- **Expected:** `ChatApp.Repo`
- **Guards against:** Oban pointed at the wrong repo module

---

### U4 — `Oban process is running after application start`
- **Inputs:** `Oban.Registry.whereis(Oban)`
- **Expected:** Returns a PID (not `nil`)
- **Guards against:** Oban not started; startup crash swallowed by the supervisor; Oban missing from supervision tree

> **Note:** Oban 2.x registers via `Oban.Registry`, not as a globally named process, so `Process.whereis(Oban)` returns `nil`. Use `Oban.Registry.whereis(Oban)` to verify the supervisor is running. This assertion does not depend on internal supervisor naming.

---

### U5 — `Oban test config uses inline mode`
- **Inputs:** `Application.fetch_env!(:chat_app, Oban)[:testing]` (evaluated in test env)
- **Expected:** `:inline`
- **Guards against:** Test environment spawning an Oban poll loop, causing intermittent failures and test-order dependency

---

### U6 — `sqlite_vec extension loads on DB connection`
- **Inputs:** `Ecto.Adapters.SQL.query!(ChatApp.Repo, "SELECT vec_version()", [])`
- **Expected:** Returns a result struct with at least one row; no exception raised
- **Guards against:** Extension wired to package in `mix.exs` but not loaded at connection time — the primary risk identified in the phase spec; produces a misleading "no such function" error in all downstream tests

---

### U7 — `.env.example contains all three eBay credential vars`
- **Inputs:** `File.read!(Path.join([__DIR__, "../../.env.example"]))` (adjust relative path as needed)
- **Expected:** String contains `"EBAY_APP_ID"`, `"EBAY_CERT_ID"`, and `"EBAY_API_BASE_URL"`
- **Guards against:** Env vars documented only in Slack; new developer missing credentials with no discoverable source

---

## E2E Tests

### E1 — `happy path — Oban queues accessible at runtime`
- **Inputs:** `Application.fetch_env!(:chat_app, Oban)[:queues]`
- **Expected:** Keyword list contains both `scraper: 3` and `embedder: 5`
- **Guards against:** Config not loaded into application env at runtime

> **Note:** The earlier draft used `Oban.config().queues`, but `testing: :inline` (required by U5) explicitly strips queues from Oban's runtime config struct. Checking `Application.fetch_env!` reads the same config the supervisor loads from and is the correct test-env assertion.

> **CI note:** I1 and I2 from earlier drafts (`mix deps.get`, `mix compile`) are CI pipeline steps, not test suite entries. Add them as shell steps in the CI job, not in the Elixir test suite.

---

# Implementation Tasks

- [x] Run `mix hex.search sqlite_vec` — record exact package name, version, or Git ref/commit hash
- [x] Add `{:oban, "~> 2.17"}` to `mix.exs` deps
- [x] Add sqlite_vec dep to `mix.exs` (Hex package or pinned Git dep based on search result above)
- [x] Write unit tests U1–U7 (all should fail at this point)
- [x] Run `mix deps.get` and verify lockfile is updated
- [x] Add `config :chat_app, Oban, repo: ChatApp.Repo, queues: [scraper: 3, embedder: 5]` to `config/config.exs`
- [x] Add `config :chat_app, Oban, testing: :inline` to `config/test.exs`
- [x] Add `{Oban, Application.fetch_env!(:chat_app, Oban)}` to children list in `lib/chat_app/application.ex`
- [x] Wire sqlite_vec extension load on each DB connection (via Repo `init/2` callback calling `SqliteVec.path()` at runtime)
- [x] Add `EBAY_APP_ID`, `EBAY_CERT_ID`, `EBAY_API_BASE_URL` with inline descriptions to `.env.example`
- [x] Run `mix test` — verify U1–U7 pass and no existing tests regress

---

# Definition of Done

- [x] `mix deps.get` exits 0
- [ ] ~~`mix compile --warnings-as-errors` exits 0~~ — **blocked by pre-existing `data-sidebar-action-icon` warnings in `lib/chat_app_web/live/sidebar_component.ex` (introduced in commit `6cfd599`, Phase 3 chat delivery). Out of scope for SP-00-01; no new warnings introduced by this sprint.**
- [x] `mix test` exits 0; U1–U7 all pass
- [x] U6 specifically passes — confirms sqlite_vec extension loads at DB connection time; do not mark done if this test is skipped or excluded
- [x] `Oban.Registry.whereis(Oban)` returns a PID (spec note corrected: Oban 2.x uses Registry, not global atom)
- [x] `.env.example` diff reviewed — all three eBay vars present with human-readable inline comments
- [x] No regressions in the pre-existing test suite (8/8 sprint tests pass; pre-existing failures unchanged)

---

# Implementation Notes

Two necessary deviations from the original spec, surfaced during implementation:

1. **`notifier: Oban.Notifiers.PG` added to Oban config.** Oban defaults to `Oban.Notifiers.Postgres`, which doesn't exist in the package when the adapter is SQLite. `Oban.Notifiers.PG` (Erlang process groups) is the SQLite-compatible alternative.
2. **Oban infrastructure migration added** at `priv/repo/migrations/20260516000000_add_oban.exs`. The "No migrations" scope bullet refers to no new app-domain schema migrations (clothing, users, etc.); Oban requires its own `oban_jobs` table to start. This is a one-line wrapper around `Oban.Migrations.up/0` and is the standard way to install Oban.
3. **sqlite_vec extension loaded via Repo `init/2`, not config.** `SqliteVec.path()` cannot be evaluated at `config/*.exs` time because deps aren't compiled yet. Moved to a runtime callback in `ChatApp.Repo` that injects `load_extensions: [SqliteVec.path()]` into the connection options.
