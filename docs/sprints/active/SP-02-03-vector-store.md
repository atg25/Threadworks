---
id: SP-02-03
phase: 2
slug: vector-store
status: active
created: 2026-05-11
activated_date: 2026-05-11
depends_on:
  - SP-02-01  # test/fixtures/embeddings.exs must be committed
estimated_days: 1.5
---

# SP-02-03 — VectorStore

**Goal:** Implement `VectorStore` with sqlite-vec upsert and KNN search, verified by a round-trip integration test using committed fixture embeddings.

---

## Scope

### In
- `lib/chat_app/search/vector_store.ex` — `upsert/2` and `search/2`
- `ChatApp.AI.VectorCodec` for encode/decode (already implemented)
- SQL against `clothing_vec` virtual table (already migrated, `vec0(embedding float[512])`)
- Integration tests using fixture embeddings from SP-02-01

### Out
- FTS5Index, QueryProcessor, HybridEngine (other search modules)
- EmbedWorker (already calls VectorStore in SP-01-07; not re-tested here)
- Any scraping or ETL code

---

## sqlite-vec Notes

- `clothing_vec` is a `vec0` virtual table. Rowid = `item_id` passed to `upsert/2`.
- The MATCH query syntax is: `WHERE embedding MATCH ?` with a VectorCodec-encoded binary as the parameter.
- The library returns `rowid` and `distance`. Distance is float, ASC sort = closest first.
- **Smoke-test immediately** after first run: if the MATCH syntax is wrong for the installed Hex version, every downstream sprint is blocked. Pin the exact Hex version in `mix.exs` before writing any test.

---

## Tests

> **All integration and E2E tests require `DataCase` (DB sandbox).**
> **Fixture vectors (`fixture_a`, `fixture_b`, `fixture_c`) must be loaded from `test/fixtures/embeddings.exs`.**

### Unit

**T-01 — `upsert/2` returns `:ok` for a valid item_id and 512-dim vector**
- Inputs: `upsert(99, fixture_a)`
- Expected: `:ok`
- Failure guarded: insert failure silently swallowed — item never searchable

**T-02 — `upsert/2` raises `ArgumentError` for a vector shorter than 512 elements**
- Inputs: `upsert(1, List.duplicate(1.0, 100))`
- Expected: `ArgumentError` raised (propagated from `VectorCodec.encode/1`)
- Failure guarded: short vector silently encoded as fewer bytes, corrupting KNN distances for all queries

**T-03 — `upsert/2` raises `ArgumentError` for a vector longer than 512 elements**
- Inputs: `upsert(1, List.duplicate(1.0, 600))`
- Expected: `ArgumentError` raised
- Failure guarded: oversized vector silently truncated or stored as wrong-length blob

**T-04 — `upsert/2` raises `FunctionClauseError` when vector contains string elements**
- Inputs: `upsert(1, List.duplicate("x", 512))`
- Expected: `FunctionClauseError` raised — propagated from `VectorCodec.encode/1`; note that *integer* elements are accepted by VectorCodec (documented behavior)
- Failure guarded: string elements silently coerced to garbage float bytes stored in vec0

**T-05 — `search/2` returns an empty list when the table is empty**
- Inputs: no prior upserts; `search(fixture_a, 5)`
- Expected: `[]`
- Failure guarded: crash or exception on KNN scan of empty virtual table

**T-06 — `search/2` returns at most `top_n` results**
- Inputs: upsert 10 distinct items with fixture vectors; `search(fixture_a, 3)`
- Expected: `length(result) <= 3`
- Failure guarded: LIMIT clause ignored; all rows returned

**T-07 — `search/2` result elements are `{integer(), float()}` tuples**
- Inputs: upsert item 42, `search(fixture_a, 5)`
- Expected: result is a list of `{item_id, distance}` tuples where `item_id` is an integer and `distance` is a float
- Failure guarded: wrong types causing pattern match failure in HybridEngine rank-building step

### Integration

**I-01 — `upsert/2 → search/2` round-trip: self-distance is less than 0.001**
- Inputs: `upsert(99, fixture_a)`, then `search(fixture_a, 5)`
- Expected: first element is `{99, d}` where `d < 0.001`
- Failure guarded: VectorCodec encode/decode mismatch or wrong byte order producing large self-distance

**I-02 — `search/2` ranks closer vector before distant vector**
- Inputs: `upsert(1, fixture_a)`, `upsert(2, fixture_b)`; `search(fixture_a, 2)`
- Expected: `[{1, _}, {2, _}]` — item 1 (fixture_a) appears before item 2 (fixture_b)
- Failure guarded: ASC/DESC sort direction inverted; most distant result returned first

**I-03 — `upsert/2` is idempotent — calling it three times does not create duplicate rows**
- Inputs: `upsert(99, fixture_a)` called three times
- Expected: `search(fixture_a, 10)` returns a list where `Enum.count(result, fn {id, _} -> id == 99 end) == 1` — exactly one entry for item_id 99
- Failure guarded: `INSERT` without `OR REPLACE` accumulating duplicate vec0 entries; inflated KNN results; incorrect rank scores in HybridEngine

**I-04 — `upsert/2` second call with different vector replaces first**
- Inputs: `upsert(99, fixture_a)`, then `upsert(99, fixture_b)`, then `search(fixture_b, 1)`
- Expected: `[{99, d}]` where `d < 0.001` — fixture_b won; fixture_a is gone
- Failure guarded: second upsert ignored; stale vector remaining searchable

**I-05 — `search/2` result rowid equals the `item_id` passed to `upsert/2`**
- Inputs: `upsert(42, fixture_a)` where 42 is not the autoincrement default; `search(fixture_a, 5)`
- Expected: returned item_id is `42`, not an internal sequence number
- Failure guarded: vec0 rowid mapping using internal sequence instead of the provided item_id, causing all HybridEngine fetches to hit wrong rows

**I-06 — `search/2` returns item_id for a vector even after the corresponding `clothing_items` row is deleted**
- Inputs: create a `clothing_items` row, `upsert(item.id, fixture_a)`, delete the `clothing_items` row, `search(fixture_a, 5)`
- Expected: `[{item.id, _}]` still returned — VectorStore has no FK awareness; orphan cleanup is the caller's responsibility
- Failure guarded: assumption that VectorStore auto-removes orphaned vectors, creating a ghost-entry bug where HybridEngine silently skips results

### E2E

**E-01 — Positive: upsert three fixtures, search with fixture_a returns fixture_a item first**
- Inputs: `upsert(1, fixture_a)`, `upsert(2, fixture_b)`, `upsert(3, fixture_c)`; `search(fixture_a, 3)`
- Expected: first element is `{1, d}` where `d < 0.001`; items 2 and 3 follow in any order
- Failure guarded: end-to-end ranking correctness broken at any layer (codec, query, sort)

**E-02 — Negative: search on empty table returns `[]` without crashing**
- Inputs: fresh DB sandbox; `search(fixture_a, 10)`
- Expected: `[]`
- Failure guarded: sqlite-vec raising on KNN scan of empty virtual table

**E-03 — Negative: upsert with string-element vector raises before reaching DB**
- Inputs: `upsert(1, List.duplicate("bad", 512))`
- Expected: `FunctionClauseError` raised in application code — no SQL executed, no partial write to DB
- Failure guarded: garbage bytes written to vec0; exception appearing as a confusing DB-layer error rather than a clear type error

---

## Implementation Tasks

- [x] Pin sqlite-vec Hex version in `mix.exs` (do not use `~>` without checking release notes)
- [x] **Smoke test immediately**: open `iex -S mix`, create a test vec0 table manually, run a MATCH query, confirm the syntax works with the installed version. If it fails, fix the version before writing any other code
- [x] Write all unit tests (T-01 through T-07) — all fail
- [x] Write integration tests (I-01 through I-06) — all fail
- [x] Write E2E tests (E-01 through E-03) — all fail
- [x] Create `lib/chat_app/search/vector_store.ex`
- [x] Implement `upsert/2`:
  - [x] Encode vector with `VectorCodec.encode/1` (let ArgumentError/FunctionClauseError propagate)
  - [x] Execute `DELETE + INSERT` (vec0 does not honour `OR REPLACE`; see implementation note)
  - [x] Return `:ok`
- [x] Implement `search/2`:
  - [x] Encode query vector with `VectorCodec.encode/1`
  - [x] Execute `SELECT rowid, distance FROM clothing_vec WHERE embedding MATCH ? ORDER BY distance LIMIT ?`
  - [x] Return `[{item_id, distance}]` as `[{integer(), float()}]`
- [x] Run all tests — all green

### Implementation notes (recorded 2026-05-11)

**Smoke test result:** PASS — Hex pkg `sqlite_vec 0.1.0`, native lib `0.1.5`. `WHERE embedding MATCH ?` syntax confirmed working against the real `clothing_vec` table with `{:blob, blob}` parameter.

**`INSERT OR REPLACE` unsupported by vec0:** The `OR REPLACE` conflict clause raises `UNIQUE constraint failed on clothing_vec primary key` on a second insert for the same rowid. Upsert is implemented as `DELETE WHERE rowid = ? + INSERT` instead. This is idempotent and satisfies I-03 and I-04.

**VectorCodec FunctionClauseError:** The sprint spec requires `FunctionClauseError` for string-element vectors (T-04, E-03). The existing `VectorCodec.encode/1` raised `ArgumentError` from the bit-syntax constructor. Fixed by routing through a private `encode_element/1 when is_number(f)` helper so the FunctionClauseError is raised on pattern-match failure for non-numeric elements. This is consistent with VectorCodec's own documented contract and its U9 test (which accepts either error).

---

## Definition of Done

- [x] All 16 tests green (`mix test test/integration/search/vector_store_test.exs`)
- [x] Round-trip self-distance < 0.001 (I-01 green)
- [x] Idempotency confirmed — no duplicate vec0 rows (I-03 green)
- [x] sqlite-vec Hex version pinned exactly in `mix.exs` and documented in a comment
- [x] Smoke test completed and result recorded (pass/fail + version used) in sprint notes before any implementation
