---
sprint_id: SP-01-06
phase: 1
status: complete
activated_date: 2026-05-11
completed_date: 2026-05-11
prerequisites: SP-01-01, SP-01-02, SP-01-03, SP-01-04, SP-01-05 all complete
estimated_days: 1.5
---

# SP-01-06 — ScrapeWorker

**Goal:** Implement `ScrapeWorker` to orchestrate all three adapters, normalize, deduplicate, and enqueue batched `EmbedWorker` jobs, so one Oban job drives the full fetch-to-persistence path for a single source and query.

---

## Scope

**In:**
- `lib/chat_app/etl/workers/scrape_worker.ex`
- `test/chat_app/etl/workers/scrape_worker_test.exs`
- Bypass mocks for all three source adapters (reuses fixtures from SP-01-01)

**Out:** `EmbedWorker` implementation — ScrapeWorker enqueues `EmbedWorker` jobs but does not execute them. `Oban` is configured as `testing: :inline` in test env, which means enqueued jobs are executed immediately unless overridden. Tests that need to count enqueued-but-not-executed jobs must use `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`.

---

## Worker Contract

```elixir
use Oban.Worker, queue: :scraper, max_attempts: 3

def perform(%Job{args: %{"source" => source, "query" => query}}) do
  # fetch → normalize → upsert_all → chunk → enqueue EmbedWorker per chunk
end
```

After `Deduplicator.upsert_all/1` returns `{:ok, items}`, enqueue one `EmbedWorker` job per 20-item chunk:
```elixir
items
|> Enum.chunk_every(20)
|> Enum.each(fn chunk ->
  %{"item_ids" => Enum.map(chunk, & &1.id)}
  |> EmbedWorker.new()
  |> Oban.insert!()
end)
```

`EmbedWorker` jobs use DB-assigned integer `id` fields, **not** `source_id` strings.

---

## Test Suite

**File:** `test/chat_app/etl/workers/scrape_worker_test.exs`
**Case:** `use ChatApp.DataCase` — DB sandbox required for persistence assertions

Each test's `setup`:
1. Start Bypass instances for all sources being exercised
2. Set `Application.put_env` for each source's base URL
3. Seed eBay ETS cache with valid token (avoids OAuth round-trip)

Oban testing mode is `manual` for job-count assertions (wraps the relevant test body in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)`).

### E2E Tests (acceptance criteria from phase spec)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `perform/1 eBay source: ≥ 20 items persisted with non-null required fields` | `ScrapeWorker.perform(%Job{args: %{"source" => "ebay", "query" => "vintage levi"}})`; Bypass returns `ebay_search_response.json` | `ClothingItem \|> where(source: "ebay") \|> Repo.aggregate(:count) >= 20`; all rows have non-nil `title`, `price`, `source_id`, `url` | Normalizer not called; Deduplicator not called; fields nil from bad mapping |
| 2 | `perform/1 25 items → exactly 2 EmbedWorker jobs enqueued (chunks: 20 + 5)` | Bypass returns 25 items; wrap in `Oban.Testing.with_testing_mode(:manual, fn -> ... end)` | `Oban.Job \|> where(worker: "ChatApp.ETL.Workers.EmbedWorker") \|> Repo.aggregate(:count) == 2` | Chunk size off (all 25 in one job; 25 individual jobs) |
| 3 | `perform/1 EmbedWorker job args: first job has 20 item_ids, second has 5` | Same setup as test 2 | Fetch both jobs; `hd(jobs).args["item_ids"] \|> length() == 20`; `last(jobs).args["item_ids"] \|> length() == 5` | IDs counted wrong; item_ids are source_ids not DB ids |
| 4 | `perform/1 EmbedWorker item_ids are DB integer ids, not source_id strings` | Same setup as test 2; fetch one EmbedWorker job | `Enum.all?(args["item_ids"], &is_integer/1) == true` | source_id strings used; EmbedWorker's `Repo.get` fails with type mismatch |

### Integration Tests

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 5 | `perform/1 returns :ok on success` | Valid Bypass setup; call `perform/1` | `:ok` returned (Oban expects `:ok` to mark job complete) | `{:ok, _}` returned instead of bare `:ok`; Oban treats non-`:ok` as failure |
| 6 | `perform/1 eBay source HTTP failure: returns {:error, reason}, no crash` | Bypass returns 500 for eBay search | `{:error, _}` returned; no exception raised; Oban will retry | Uncaught error raises; job marked as discarded instead of retried |
| 7 | `perform/1 items tagged with correct source after persist` | eBay Bypass; call `perform/1` with source: "ebay" | All persisted items have `source: "ebay"` | Source field lost between normalize and upsert |
| 8 | `max_attempts is 3` | Inspect module attribute or `ScrapeWorker.__oban_worker_opts__()` | `opts[:max_attempts] == 3` | Default max_attempts used (which differs across Oban versions); retries silently capped |

### Concurrency Tests (assigned from QA review)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 9 | `two concurrent perform/1 calls same source+query: no unique constraint errors` | `Task.async_stream([1, 2], fn _ -> ScrapeWorker.perform(%Job{args: %{"source" => "ebay", "query" => "vintage levi"}}) end, max_concurrency: 2) \|> Enum.to_list()`; both Bypass calls return same 20 items | Both tasks return `{:ok, _}` or `{:error, _}`; no `Ecto.ConstraintError` raised | Deduplicator's `on_conflict` not wired; second job crashes on unique index violation |
| 10 | `two concurrent perform/1 calls same source+query: price_history count == 2N` | Same setup; N items returned by Bypass | `Repo.aggregate(PriceHistory, :count) == 2 * N` | Price history written by only one of the concurrent workers; race on insert |

---

## Implementation Tasks (TDD Order)

1. ✅ **Write all 10 tests** — all red.
2. ✅ **Create `lib/chat_app/etl/workers/scrape_worker.ex`** — `use Oban.Worker, queue: :scraper, max_attempts: 3`; `perform/1` returns `{:error, :not_implemented}`.
3. ✅ **Wire adapter dispatch** — `case source do "ebay" -> Ebay.fetch_items(query); "depop" -> Depop.fetch_items(query); "poshmark" -> Poshmark.fetch_items(query) end`. Test 6 (error return) goes green first.
4. ✅ **Wire Normalizer** — map raw items through `Normalizer.normalize(source, raw)`. Test 7 goes green.
5. ✅ **Wire Deduplicator** — call `Deduplicator.upsert_all(normalized_items)`; receive `{:ok, items}`. Tests 1, 5 go green.
6. ✅ **Implement EmbedWorker job enqueueing** — chunk items by 20; `EmbedWorker.new(%{"item_ids" => ids}) |> Oban.insert!()`. Tests 2–4 go green.
7. ✅ **Verify `:ok` return** — ensure `perform/1` returns bare `:ok` on success path. Test 5 confirmed.
8. ✅ **Run concurrency tests** (9–10) — if unique constraint errors appear, confirm Deduplicator's `on_conflict` is wired. These tests may already pass from SP-01-05's correct upsert implementation.
9. ✅ **Run all 10 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/workers/scrape_worker_test.exs` — 10/10 green, zero skips
- Tests 2–4 use `Oban.Testing.with_testing_mode(:manual, ...)` — EmbedWorker not executed during these tests
- Test 9 passes without `Ecto.ConstraintError` — concurrent scrapes are safe
- Test 10 confirms price_history count is `2N` — both concurrent workers write history
- `mix compile --warnings-as-errors` clean
- `ScrapeWorker.perform/1` returns bare `:ok` (not `{:ok, _}`) on success — verified by test 5
