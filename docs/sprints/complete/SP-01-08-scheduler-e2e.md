---
sprint_id: SP-01-08
phase: 1
status: complete
activated_date: 2026-05-11
completed_date: 2026-05-11
prerequisites: SP-01-01 through SP-01-07 all complete
estimated_days: 1
---

# SP-01-08 — Scheduler + Full E2E

**Goal:** Wire the Oban cron scheduler, verify it registers correctly after application start, and validate the complete scrape → normalize → deduplicate → embed pipeline end-to-end under both success and failure conditions.

---

## Scope

**In:**
- Add `Oban.Plugins.Cron` to Oban config in `config/config.exs` with `ScrapeWorker` on `"0 */2 * * *"`
- Add `:scrape_queries` config key to `config/config.exs` and `config/test.exs`
- `test/chat_app/etl/scheduler_test.exs` — scheduler registration and config tests
- `test/chat_app/etl/pipeline_e2e_test.exs` — full pipeline end-to-end tests

**Out:** No new library modules. This sprint only wires configuration and writes capstone tests over all previously implemented modules.

---

## Configuration

Add to `config/config.exs`:
```elixir
config :chat_app, :scrape_queries, [
  "vintage levi",
  "y2k denim",
  "silk slip dress",
  "90s windbreaker",
  "cashmere sweater"
]
```

Update Oban config in `config/config.exs`:
```elixir
config :chat_app, Oban,
  repo: ChatApp.Repo,
  queues: [scraper: 3, embedder: 5],
  notifier: Oban.Notifiers.PG,
  plugins: [
    {Oban.Plugins.Cron,
      crontab: [
        {"0 */2 * * *", ChatApp.ETL.Workers.ScrapeWorker,
         args: %{"queries" => Application.get_env(:chat_app, :scrape_queries, [])}}
      ]}
  ]
```

Add to `config/test.exs`:
```elixir
config :chat_app, :scrape_queries, ["test query"]
```

> `config :chat_app, Oban, testing: :inline` in `config/test.exs` stays unchanged — the inline mode handles the E2E test job drain. For scheduler registration tests, the Oban cron plugin must be running; use `Oban.Testing` helpers to inspect scheduled jobs without triggering them.

---

## Test Suite

### Scheduler Tests

**File:** `test/chat_app/etl/scheduler_test.exs`
**Case:** `use ChatApp.DataCase`

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `ScrapeWorker jobs exist in oban_jobs after application start` | `Oban.Job \|> where(worker: "ChatApp.ETL.Workers.ScrapeWorker") \|> Repo.aggregate(:count)` | Count > 0 (Cron plugin inserts scheduled jobs on startup) | Cron plugin not added to Oban config; wrong worker module string in crontab |
| 2 | `Cron expression is "0 */2 * * *" and not "*/2 * * * *"` | Fetch the ScrapeWorker cron job from `oban_jobs`; inspect `scheduled_at` cadence OR inspect Oban config directly | Cron string in config is exactly `"0 */2 * * *"` | `"*/2 * * * *"` used instead — fires every 2 minutes, not every 2 hours; 60× the intended rate |
| 3 | `:scrape_queries config key is accessible in test environment` | `Application.fetch_env!(:chat_app, :scrape_queries)` | Returns `["test query"]` (from `config/test.exs`); does not raise `ArgumentError` | Key missing from test config; `fetch_env!` raises; ScrapeWorker crashes on first perform |
| 4 | `:scrape_queries is overridable via Application.put_env in tests` | `Application.put_env(:chat_app, :scrape_queries, ["custom"])`; assert config reads back `["custom"]` | `Application.get_env(:chat_app, :scrape_queries) == ["custom"]` | Queries hardcoded in worker module attribute at compile time (not runtime-readable) |

### E2E Tests

**File:** `test/chat_app/etl/pipeline_e2e_test.exs`
**Case:** `use ChatApp.DataCase`

Each test's `setup`:
1. Start Bypass instances for all three source endpoints + OpenAI embeddings
2. Set all base URL application envs
3. Seed eBay ETS token cache
4. `Oban` already in `:inline` mode — jobs execute synchronously on insert

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 5 | `full pipeline: scrape → normalize → deduplicate → embed: all items have embedding` | `ScrapeWorker.perform(ebay job)`; Bypass returns 20 items for search, OpenAI returns 20 embeddings | `ClothingItem \|> where(source: "ebay") \|> Repo.all()` all have non-nil `embedding` with `byte_size == 2048`; `Repo.query!("SELECT count(*) FROM clothing_vec").rows == [[20]]` | Worker hand-off broken (EmbedWorker not enqueued or not executed); VectorCodec error silently skips embedding |
| 6 | `full pipeline idempotency: second run same item count, doubled price_history` | Run full pipeline twice with same Bypass mock | After first run: `count_items() == 20`, `count_price_history() == 20`. After second run: `count_items() == 20`, `count_price_history() == 40` | Deduplication broken; unique constraint error on second run; price_history written once per item lifetime instead of per run |
| 7 | `full pipeline: eBay source HTTP failure isolated — other sources still persist` | eBay Bypass returns 500; Depop and Poshmark Bypass return valid fixtures | Depop and Poshmark items persisted (`source` in `["depop", "poshmark"]`); eBay items count == 0; no unhandled exception | Single source failure crashes entire worker; no partial saves |

---

## Implementation Tasks (TDD Order)

1. ✅ **Write all 7 tests** — all red.
2. ✅ **Add `:scrape_queries` to `config/config.exs` and `config/test.exs`** — tests 3–4 go green.
3. ✅ **Add `Oban.Plugins.Cron`** to Oban config in `config/config.exs` as shown above — test 1 goes green.
4. ✅ **Verify cron expression** — test 2 passes if the string is `"0 */2 * * *"`. If test fails, the expression is wrong; fix it before continuing.
5. ✅ **Run E2E tests** (5–7) — these exercise the full stack assembled in SP-01-01 through SP-01-07. Failures at this stage indicate integration gaps between sprints, not new code bugs. Diagnose by layer:
   - Test 5 fails at embedding step → check `openai_embeddings_url` config wiring
   - Test 6 fails on item count → check Deduplicator conflict target
   - Test 6 fails on price_history count → check price_history always-write in Deduplicator
   - Test 7 fails with exception → check ScrapeWorker source error isolation *(fixed: `coerce_price` now strips `$` prefix before `Decimal.new`)*
6. ✅ **Run all 7 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/scheduler_test.exs test/chat_app/etl/pipeline_e2e_test.exs` — 7/7 green, zero skips
- Test 2 (cron expression) passes — `"0 */2 * * *"` confirmed, not `"*/2 * * * *"`
- Test 6 (idempotency) passes — `count_price_history() == 40` after two runs confirmed
- `mix test` (full suite) green — no regressions introduced by Oban cron config change
- `mix compile --warnings-as-errors` clean
- Phase 1 acceptance criteria from spec all covered by named tests:
  - Scrape + normalize (mocked): test 5
  - Idempotency: test 6
  - Price history: test 6
  - EmbedWorker batching: SP-01-06 tests 2–4
  - OAuth token refresh: SP-01-02 test 2
  - Scheduler registration: test 1
