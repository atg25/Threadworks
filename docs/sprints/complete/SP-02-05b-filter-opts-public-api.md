---
id: SP-02-05b
phase: 2
slug: filter-opts-public-api
status: complete
created: 2026-05-11
activated_date: 2026-05-12
completed_date: 2026-05-12
depends_on:
  - SP-02-05a  # HybridEngine core must be complete and all core tests green
estimated_days: 1
---

# SP-02-05b — Filter Opts + Public API

**Goal:** Add `source`, `max_price`, `size`, and `limit` filter opts to `HybridEngine.search/2` as pre-fetch WHERE conditions, and expose `ChatApp.Clothing.search_hybrid/2` as the sole public entry point.

---

## Scope

### In
- Filter opts applied as SQL `WHERE` conditions in the `Repo.all` DB fetch (not post-hydration in Elixir)
- `source: :ebay | :depop | :poshmark | nil`
- `max_price: Decimal.t() | nil`
- `size: String.t() | nil`
- `limit: integer()` — default `10`, applied to RRF result list before DB fetch
- `ChatApp.Clothing.search_hybrid/2` delegation function in `lib/chat_app/clothing.ex`

### Out
- Changes to HybridEngine core pipeline (must not modify T-01 through E-03 from SP-02-05a)
- Any UI wiring (future sprint)
- New migrations or schema changes

---

## Design Decision: `size` Filter Case Sensitivity

The spec says `size: String.t()` and the schema stores `size` as a plain string. **The filter uses exact case-insensitive matching**: `WHERE LOWER(i.size) = LOWER(?)`. Rationale: scrapers across eBay/Depop/Poshmark may normalize size differently ("M", "m", "Medium"). Exact-match would silently miss valid results.

If the spec author intended exact match, this decision must be overridden before implementation. It is encoded in test I-03 below.

---

## Tests

> **All tests require `DataCase` (DB sandbox).**
> **Embedder is always mocked.**

### Integration

**I-01 — `source` filter excludes items from other sources**
- Inputs: seed items: one with `source: "ebay"`, one with `source: "depop"`; upsert both vectors and FTS; Embedder mock; `search("jacket", source: :ebay)`
- Expected: result contains only the ebay item; depop item absent
- Failure guarded: filter ignored; both items returned regardless of source

**I-02 — `max_price` filter excludes over-budget items**
- Inputs: seed items at prices `"10.00"`, `"50.00"`, `"200.00"`; upsert all; `search("jacket", max_price: Decimal.new("30"))`
- Expected: result does not contain the `$50` or `$200` items; may contain the `$10` item if it matches the query
- Failure guarded: Decimal comparison broken (string comparison "10" < "9" lexicographically); expensive items leaking through

**I-03 — `size` filter matches case-insensitively**
- Inputs: seed items with sizes `"m"`, `"M"`, `"L"`; upsert all; `search("jacket", size: "M")`
- Expected: result includes items with size `"m"` and `"M"`; does not include item with size `"L"`
- Failure guarded: exact-match comparison missing case fold; user searching "M" misses items normalized to "m" by a specific scraper

**I-04 — `limit` returns at most N results**
- Inputs: seed 20 items all matching the query; upsert all; `search("jacket", limit: 5)`
- Expected: `{:ok, items}` where `length(items) <= 5`
- Failure guarded: limit applied to RRF list but not enforced before or after DB fetch

**I-05 — `limit: 0` returns `{:ok, []}` without crashing**
- Inputs: seeded DB; `search("jacket", limit: 0)`
- Expected: `{:ok, []}`
- Failure guarded: `LIMIT 0` or `Enum.take(list, 0)` causing unexpected error; negative downstream behavior

**I-06 — Filters are applied as SQL WHERE conditions, not post-hydration**
- Inputs: seed items with `source: "ebay"` and `source: "depop"`; `search("jacket", source: :ebay)`
- Expected: the SQL query sent to DB contains `WHERE ... AND i.source = 'ebay'` — not a post-fetch `Enum.filter`
- How to verify: use `Ecto.Adapters.SQL.explain/3` or inspect the generated query in test output; alternatively, confirm that a deleted ebay item (visible to RRF but not DB) does not appear, which only a DB-layer filter guarantees
- Failure guarded: post-hydration filtering appearing to work in tests but bypassing DB-level optimizations; deleted items leaking through if filter is applied after fetch

**I-07 — Multiple filters compose correctly**
- Inputs: seed four items: `{source: "ebay", size: "M", price: "25.00"}`, `{source: "ebay", size: "L", price: "25.00"}`, `{source: "depop", size: "M", price: "25.00"}`, `{source: "ebay", size: "M", price: "150.00"}`; upsert all; `search("jacket", source: :ebay, size: "M", max_price: Decimal.new("50"))`
- Expected: only the first item `{ebay, M, $25}` matches all three filters
- Failure guarded: filters applied independently with OR instead of AND; any single filter being ignored in composition

**I-08 — `Clothing.search_hybrid/2` delegates to `HybridEngine.search/2`**
- Inputs: `ChatApp.Clothing.search_hybrid("vintage jacket", [source: :ebay])` with seeded DB + Embedder mock
- Expected: result is identical to calling `HybridEngine.search("vintage jacket", source: :ebay)` directly
- Failure guarded: public API delegation broken (wrong arity, wrong module alias, opts not forwarded)

**I-09 — `rrf_score` values on filtered results remain correct positive floats**
- Inputs: search with `source: :ebay` filter; at least one result returned
- Expected: every returned item has `rrf_score > 0` and `rrf_score <= 2.0 / 61`; score reflects the item's pre-filter RRF rank, not recomputed after filtering
- Failure guarded: rrf_score reset to nil or zero after filter step; score recomputed from filtered subset (wrong — would change relative ordering)

### E2E

**E-01 — Positive: full pipeline through public API with source filter**
- Inputs: seed items from ebay and depop; `ChatApp.Clothing.search_hybrid("jacket", source: :ebay)` with Embedder mock
- Expected: `{:ok, items}` where all items have `source == "ebay"`; each is a `%ClothingItem{}` struct with `rrf_score > 0`
- Failure guarded: full public API pipeline broken at any step

**E-02 — Negative: all candidates filtered out by max_price → `{:ok, []}`**
- Inputs: seed items all priced `"500.00"`; `search("jacket", max_price: Decimal.new("10"))`
- Expected: `{:ok, []}` — filters applied, no results survive; no crash
- Failure guarded: empty result after filter crashing instead of returning clean empty list

---

## Implementation Tasks

- [x] Write all integration tests I-01 through I-09 — all fail
- [x] Write E2E tests E-01, E-02 — all fail
- [x] Extend `HybridEngine.search/2` to accept and apply opt filters:
  - [x] Extract `limit` from opts (default `10`); apply `Enum.take(rrf_list, limit)` before DB fetch
  - [x] Build the DB query with dynamic WHERE conditions:
    - [x] `source` filter: `where: i.source == ^source` (convert atom to string)
    - [x] `max_price` filter: `where: i.price <= ^max_price`
    - [x] `size` filter: `where: fragment("LOWER(?)", i.size) == fragment("LOWER(?)", ^size)`
  - [x] All active filters are AND-composed in a single query
  - [x] `limit: 0` handled before DB fetch (return `{:ok, []}` immediately)
- [x] Add `search_hybrid/2` to `lib/chat_app/clothing.ex`:
  ```elixir
  def search_hybrid(query_text, opts \\ []) do
    ChatApp.Search.HybridEngine.search(query_text, opts)
  end
  ```
- [x] Run all tests — all green
- [x] Run full phase 2 test suite — all previously green tests remain green

---

## Definition of Done

- [x] All 11 tests green (`mix test test/integration/search/hybrid_engine_filter_test.exs`)
- [x] Multiple filters compose with AND semantics (I-07 green)
- [x] `limit: 0` returns `{:ok, []}` (I-05 green)
- [x] `Clothing.search_hybrid/2` is the only public entry point — `HybridEngine` is not called directly from outside the `Search` namespace
- [x] Full suite (`mix test`) green — no regressions in SP-02-05a tests
- [x] `HybridEngine` module is not referenced directly in any controller, LiveView, or context module other than `ChatApp.Clothing`
