---
id: SP-02-05a
phase: 2
slug: hybrid-engine-core
status: complete
created: 2026-05-11
activated_date: 2026-05-12
completed_date: 2026-05-12
depends_on:
  - SP-02-01  # test/fixtures/embeddings.exs + Embedder
  - SP-02-02  # QueryProcessor
  - SP-02-03  # VectorStore
  - SP-02-04  # FTS5Index
estimated_days: 1.5
---

# SP-02-05a — HybridEngine Core

**Goal:** Implement the RRF fusion engine wiring vector and FTS5 search in parallel, verified by the ordering acceptance criterion (Item A before B and C), and establish error propagation contracts before filter logic is added in SP-02-05b.

---

## Scope

### In
- `lib/chat_app/search/hybrid_engine.ex` — `search/2` (core pipeline, no filter opts yet)
- Private `rrf_fuse/2` — extractable for direct unit testing
- `Task.async` parallel execution of `VectorStore.search/2` and `FTS5Index.search/2`
- `:rrf_score` virtual field on returned `%ClothingItem{}` structs
- Empty-query guard (return `{:ok, []}` immediately without calling Embedder)
- Error propagation contract when Embedder fails
- Graceful handling when items are deleted between search and DB fetch

### Out
- Filter opts (`source`, `max_price`, `size`, `limit`) — implemented in SP-02-05b
- `ChatApp.Clothing.search_hybrid/2` public API delegation — SP-02-05b
- Any scraping, ETL, or UI code

---

## Schema Change Required Before Tests

`ClothingItem` does not have an `rrf_score` field. Add a virtual field **before writing tests**, otherwise tests that assert `item.rrf_score` will raise `KeyError`.

In `lib/chat_app/clothing/item.ex`, add to the schema block:

```elixir
field :rrf_score, :float, virtual: true
```

This is a schema change that belongs in this sprint's implementation tasks.

---

## RRF Formula

For each unique `item_id` across both result lists:

```
score(item_id) = sum over each pipeline of: 1.0 / (60 + rank)
```

- `rank` is 1-based (rank 1 = best result in that pipeline)
- If an item appears in only one pipeline, it contributes one term
- If an item appears in both pipelines, it contributes two terms (one per pipeline)
- `k = 60` is fixed
- Sort by score DESC (highest score = best result)

Maximum possible score: item ranked 1 in both pipelines → `1/61 + 1/61 = 2/61 ≈ 0.0328`

---

## Tests

> **Embedder is always mocked in tests — no live API calls.**
> **Integration and E2E tests require `DataCase` (DB sandbox).**

### Unit

**T-01 — `rrf_fuse/2`: item appearing in both pipelines gets sum of both terms**
- Inputs: vector ranks `%{1 => 1, 2 => 2}`, fts ranks `%{2 => 1, 3 => 2}`
- Expected scored map (or list):
  - Item 1: `1.0 / (60 + 1) = 1/61`
  - Item 2: `1.0 / (60 + 2) + 1.0 / (60 + 1) = 1/62 + 1/61`
  - Item 3: `1.0 / (60 + 2) = 1/62`
  - Item 2 has the highest score (assert it comes first in the sorted output)
- Failure guarded: wrong RRF formula; missing addition across pipelines; integer division instead of float division

**T-02 — `rrf_fuse/2`: item in only one pipeline gets a single term**
- Inputs: vector ranks `%{5 => 3}`, fts ranks `%{}`
- Expected: item 5 score = `1.0 / (60 + 3) = 1/63`; no KeyError from missing fts entry for item 5
- Failure guarded: crash on absent key in rank map; nil arithmetic

**T-03 — `rrf_fuse/2`: rank-1 item in both pipelines equals 2/61**
- Inputs: vector ranks `%{7 => 1}`, fts ranks `%{7 => 1}`
- Expected: item 7 score = `2.0 / 61` within floating-point epsilon
- Failure guarded: off-by-one in k constant (using 59 or 61 instead of 60)

**T-04 — `rrf_fuse/2` output is sorted DESC by score**
- Inputs: vector ranks `%{1 => 1, 2 => 2, 3 => 3}`, fts ranks `%{3 => 1, 2 => 2, 1 => 3}`
- Expected: returned list is sorted so higher-scored items appear first
- Failure guarded: ascending sort returning worst-ranked items first

**T-05 — All `rrf_score` values on returned items are positive floats ≤ 2/61**
- Inputs: any `search/2` call returning at least one result (use seeded DB + mocked Embedder)
- Expected: every `item.rrf_score` satisfies `item.rrf_score > 0 and item.rrf_score <= 2.0 / 61`
- Failure guarded: score computed as zero (integer division `1 / 61 = 0`); score exceeding maximum (wrong formula doubling instead of summing)

### Integration

**I-01 — `search/2` returns `{:ok, []}` when DB has no items**
- Inputs: fresh DB sandbox (no `clothing_items`); Embedder mock returning `fixture_a`; `HybridEngine.search("vintage jacket")`
- Expected: `{:ok, []}`
- Failure guarded: crash when both rank maps are empty; nil error in rrf_fuse; DB fetch of empty id list failing

**I-02 — `search/2` returns `{:ok, []}` for empty query string without calling Embedder**
- Inputs: `HybridEngine.search("")`; Embedder mock configured to raise `RuntimeError` if called
- Expected: `{:ok, []}`; Embedder is never invoked
- Failure guarded: empty query causing unnecessary API call (wasted cost); FTS5 empty MATCH crashing; guard missing

**I-03 — `search/2` propagates Embedder error as `{:error, reason}`**
- Inputs: Embedder mock returns `{:error, :api_down}`; seeded DB; `HybridEngine.search("jacket")`
- Expected: `{:error, :api_down}` — not `{:ok, []}`, not a raised exception
- Failure guarded: error silently swallowed returning empty results (misleadingly suggests no results exist); unhandled pattern match crash propagating to caller

**I-04 — `search/2` returns `%ClothingItem{}` structs with a positive `:rrf_score` float**
- Inputs: seed DB with 2 items; upsert vectors and FTS; Embedder mock returns `fixture_a`; `search("vintage jacket")`
- Expected:
  - Result is `{:ok, items}` where `length(items) >= 1`
  - Each element passes `is_struct(item, ChatApp.Clothing.Item)` — not a plain map
  - Each element has `item.rrf_score` that is a positive float
- Failure guarded: `Map.put` used instead of virtual schema field, breaking struct pattern matches; rrf_score missing or nil

**I-05 (Acceptance criterion) — Item A ranks before Items B and C**
- Inputs:
  - Insert three `clothing_items` rows corresponding to fixture definitions (A = "vintage levi denim jacket secondhand", B = "pink silk evening gown formal wear", C = "denim jacket indigo blue worn preloved")
  - Upsert all three vectors into `clothing_vec`
  - Upsert all three FTS entries into `clothing_fts`
  - Embedder mock returns `fixture_a` for query `"vintage levi denim jacket"`
  - `HybridEngine.search("vintage levi denim jacket")`
- Expected: `{:ok, [first | _]}` where `first.id == item_a.id`
- Failure guarded: RRF ranking inversion; fixture wiring error; vector or FTS upsert not run in test setup; rrf_score comparison bug; wrong sort direction

**I-06 — `search/2` completes without hanging (use short ExUnit timeout)**
- Add `@tag timeout: 1_000` to this test
- Inputs: `search("jacket")` with mocked Embedder and seeded DB
- Expected: result returned within 1 second
- Failure guarded: `Task.await/1` without explicit timeout causing infinite hang if a sub-task blocks; missing `Task.await` call leaving tasks running but result never collected

**I-07 — `search/2` handles a Task exception from VectorStore without crashing the caller**
- Inputs: VectorStore mock that raises `RuntimeError` when called; `HybridEngine.search("jacket")`
- Expected: `{:error, _}` returned — the RuntimeError is caught and converted to an error tuple; the calling process does not crash
- Failure guarded: Task exception re-raised by `Task.await`, crashing the LiveView or API handler process

**I-08 — Items deleted between search and DB fetch are silently dropped from results**
- Inputs: upsert vectors and FTS for items A and B; delete item B's `clothing_items` row (leave vec and FTS orphaned); `search("matching query")` with Embedder mock
- Expected: result contains item A; does not contain item B; no error raised
- Failure guarded: `Repo.all` with `IN` clause returning nil for deleted IDs; crash on nil struct; wrong assumption that HybridEngine should error on orphaned vectors

### E2E

**E-01 — Positive: end-to-end with fixture embeddings — Item A first**
- Inputs: full setup (insert items A, B, C; upsert all vectors and FTS; Embedder mock returns `fixture_a`); `HybridEngine.search("vintage levi denim jacket")`
- Expected: `{:ok, [a | _]}` where `a` is a `%ClothingItem{}` struct, `a.id == item_a.id`, `a.rrf_score > 0`
- Failure guarded: full pipeline integration broken at any handoff between modules

**E-02 — Negative: both pipelines return empty → `{:ok, []}`**
- Inputs: empty DB; Embedder mock returns `fixture_a`; `search("anything")`
- Expected: `{:ok, []}`
- Failure guarded: crash when merging two empty rank maps; nil arithmetic in rrf_fuse

**E-03 — Negative: Embedder returns `{:error, _}` → `{:error, _}` propagated, not swallowed**
- Inputs: Embedder mock returns `{:error, :api_down}`; seeded DB; `search("test")`
- Expected: `{:error, :api_down}`
- Failure guarded: silent degradation returning `{:ok, []}` when the vector pipeline is broken — misleads the caller into thinking the search ran successfully with no results

---

## Implementation Tasks

- [x] Add `field :rrf_score, :float, virtual: true` to `ChatApp.Clothing.Item` schema
- [x] Write unit tests T-01 through T-05 — all fail
- [x] Write integration tests I-01 through I-08 — all fail
- [x] Write E2E tests E-01, E-02, E-03 — all fail
- [x] Create `lib/chat_app/search/hybrid_engine.ex`
- [x] Implement private `rrf_fuse/2`:
  - [x] Accept two `%{item_id => rank}` maps
  - [x] Collect all unique item_ids across both maps
  - [x] For each item_id, compute score: `Enum.sum(for {ranks, _} <- [{vec_ranks, :vec}, {fts_ranks, :fts}], rank = Map.get(ranks, id), do: 1.0 / (60 + rank))`
  - [x] Return `[{item_id, score}]` sorted DESC by score
- [x] Run T-01 through T-04 — green
- [x] Implement `search/2` core pipeline:
  - [x] Guard: if `String.trim(query_text) == ""`, return `{:ok, []}`
  - [x] Call `Embedder.embed(query_text)` — if `{:error, reason}`, return `{:error, reason}`
  - [x] Call `QueryProcessor.process(query_text)` for FTS query
  - [x] `Task.async` for `VectorStore.search(query_vector, 50)` and `FTS5Index.search(processed_query, 50)` in parallel; use `Task.await/2` with explicit timeout (e.g. 5_000ms); catch Task exceptions and convert to `{:error, reason}`
  - [x] Build rank maps: `%{item_id => rank}` from each result list (rank is 1-based position)
  - [x] Call `rrf_fuse/2` → sorted `[{item_id, score}]`
  - [x] Take first `limit` results (default 50 for now; filter opts added in SP-02-05b)
  - [x] Fetch `%ClothingItem{}` records: `Repo.all(from i in Item, where: i.id in ^ids)`
  - [x] Re-order fetched items to match RRF rank order; drop any items not returned by DB (orphans)
  - [x] Set `:rrf_score` on each struct using `%{item | rrf_score: score}`
  - [x] Return `{:ok, items}`
- [x] Run all tests — all green

---

## Definition of Done

- [x] All 16 tests green (`mix test test/integration/search/hybrid_engine_test.exs`)
- [x] Acceptance criterion (I-05) green: Item A is first result for "vintage levi denim jacket"
- [x] Every returned item is a `%ClothingItem{}` struct (not a plain map) with `rrf_score > 0`
- [x] Empty query returns `{:ok, []}` without calling Embedder (I-02 green)
- [x] Embedder error propagates as `{:error, _}` (I-03 green)
- [x] Task.await has an explicit timeout — no infinite hang possible (I-06 green)
- [x] `rrf_score` virtual field added to `ClothingItem` schema
