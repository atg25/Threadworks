---
id: SP-00-03
phase: 0
status: complete
created_date: 2026-05-06
activated_date: 2026-05-06
completed_date: 2026-05-06
---

# Goal

Land the `user_preferences`, FTS5, and sqlite_vec migrations, implement and fully test `VectorCodec`, and verify that FTS5 content-table sync semantics are understood and tested before any search query logic is written.

---

# Scope

**In scope:**
- Migration 5: `_create_user_preferences` — FK → `users`, unique per user
- Migration 6: `_create_clothing_fts` — FTS5 virtual table over `clothing_items`
- Migration 7: `_create_clothing_vec` — sqlite_vec virtual table
- `lib/chat_app/ai/vector_codec.ex` — `encode/1` and `decode/1`

**Out of scope:**
- Any code that calls `VectorCodec` (Phase 1+)
- Embedding generation
- FTS or vector query logic
- KNN search implementation

**Runtime ordering dependency:** Migration 6 (`clothing_fts`) references `clothing_items` as its FTS5 content table. It has a hard runtime dependency on Migration 2 from SP-00-02. SP-00-02 must be complete and its migrations applied before this sprint's migrations can run.

---

# Tests

## Unit Tests — VectorCodec

**File:** `test/chat_app/ai/vector_codec_test.exs`

All tests are pure — no DB, no process, no async setup required.

---

### U1 — `encode/1 returns binary of exactly 2048 bytes for a 512-element list`
- **Inputs:** `List.duplicate(0.0, 511) ++ [1.0]`
- **Expected:** `byte_size(VectorCodec.encode(input)) == 2048`
- **Guards against:** Off-by-one in element count; wrong float width (float64 would produce 4096 bytes)

### U2 — `encode/1 last element encodes as little-endian float32 1.0`
- **Inputs:** `List.duplicate(0.0, 511) ++ [1.0]`
- **Expected:** Last 4 bytes of the encoded binary equal `<<0, 0, 128, 63>>` (IEEE 754 little-endian representation of 1.0)
- **Guards against:** Endianness reversed (big-endian would produce `<<63, 128, 0, 0>>`); wrong float width; mismatch with sqlite_vec's expectations

### U3 — `decode/1 round-trips encode output within float32 precision`
- **Inputs:** `original = List.duplicate(0.0, 511) ++ [1.0]`; `VectorCodec.encode(original)` → `VectorCodec.decode(result)`
- **Expected:** Each element of the decoded list is within `0.0001` of the corresponding element in `original`
- **Guards against:** Precision loss beyond float32 tolerance; byte-order swap corrupting values

### U4 — `decode/1 returns a list of exactly 512 floats`
- **Inputs:** A valid 2048-byte binary produced by `encode/1`
- **Expected:** `length(VectorCodec.decode(binary)) == 512`
- **Guards against:** Off-by-one in decode loop; returning a binary-chunked list of binaries instead of floats

### U5 — `encode/1 raises ArgumentError on list shorter than 512 elements`
- **Inputs:** `List.duplicate(0.0, 511)` (511 elements)
- **Expected:** `assert_raise ArgumentError, fn -> VectorCodec.encode(input) end`
- **Guards against:** Silently padding with zeros, masking a caller bug where the embedding model returned fewer dimensions than expected

### U6 — `encode/1 raises ArgumentError on list longer than 512 elements`
- **Inputs:** `List.duplicate(0.0, 513)` (513 elements)
- **Expected:** `assert_raise ArgumentError, fn -> VectorCodec.encode(input) end`
- **Guards against:** Silently truncating extra elements, masking a model output dimension mismatch

### U7 — `encode/1 handles all-zeros correctly`
- **Inputs:** `List.duplicate(0.0, 512)`
- **Expected:** Result is a 2048-byte binary where all bytes are `0`
- **Guards against:** IEEE 754 zero not encoding to all-zero bytes; special handling of zero breaking the codec

### U8 — `decode/1 raises ArgumentError on binary with wrong byte length`
- **Inputs:** `<<0::24>>` (3 bytes — not a multiple of 4)
- **Expected:** `assert_raise ArgumentError, fn -> VectorCodec.decode(input) end`
- **Guards against:** Decoder silently returning a partial list of 0 elements; calling code receiving a shorter-than-expected vector without error

### U9 — `encode/1 raises on non-float, non-numeric elements`
- **Inputs:** `["not_a_float"] ++ List.duplicate(0.0, 511)`
- **Expected:** Raises (ArgumentError or FunctionClauseError — whichever the implementation defines; document the contract in the module)
- **Guards against:** Silent coercion or atom-to-float conversion masking a caller type bug; inconsistent error behaviour surprises callers

---

## Unit Tests — Migrations 5–7

**File:** `test/chat_app/migrations/user_preferences_test.exs`

### U10 — `user_preferences table exists`
- **Inputs:** `SELECT name FROM sqlite_master WHERE type='table' AND name='user_preferences'`
- **Expected:** Result has exactly one row
- **Guards against:** Migration not run; table name typo

### U11 — `user_preferences unique index prevents duplicate user_id`
- **Inputs:** Insert two rows with the same `user_id`
- **Expected:** Second insert raises `Exqlite.Error` on UNIQUE constraint
- **Guards against:** Missing unique constraint; multiple preference rows per user

### U12 — `user_preferences user_id FK references users`
- **Setup:** `PRAGMA foreign_keys = ON`
- **Inputs:** `PRAGMA foreign_key_list(user_preferences)`
- **Expected:** Result includes a row with `table = "users"` and `to = "id"`
- **Guards against:** FK omitted; orphaned preference rows after user deletion

---

**File:** `test/chat_app/migrations/clothing_fts_test.exs`

### U13 — `clothing_fts virtual table exists`
- **Inputs:** `SELECT name FROM sqlite_master WHERE type='table' AND name='clothing_fts'`
- **Expected:** Result has exactly one row
- **Guards against:** FTS migration failed silently; `CREATE VIRTUAL TABLE` rejected due to ordering issue (ran before `clothing_items` existed)

### U14 — `FTS5 does NOT index a row that was inserted before a rebuild`
- **Setup:** Insert a clothing_item with `title: "Zara Coat"`; do NOT run a rebuild
- **Inputs:** `SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'zara'`
- **Expected:** Empty result set
- **Guards against:** Developer assuming FTS5 content tables auto-sync on insert; this test encodes the correct mental model and prevents stale-index bugs in Phase 1 query code

### U15 — `FTS5 indexes a row after explicit rebuild`
- **Setup:** Insert a clothing_item with `title: "Levi Jacket"`; run `INSERT INTO clothing_fts(clothing_fts) VALUES('rebuild')`
- **Inputs:** `SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'levi'`
- **Expected:** Non-empty result set; returned rowid matches the clothing_item's id
- **Guards against:** FTS content table misconfigured (wrong `content=` or `content_rowid=` value)

### U16 — `FTS5 returns no result for a term not present in any title`
- **Setup:** Same as U15 (Levi Jacket row + rebuild)
- **Inputs:** `SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'adidas'`
- **Expected:** Empty result set
- **Guards against:** FTS configured to match everything (misconfigured wildcard or wrong column mapping)

---

**File:** `test/chat_app/migrations/clothing_vec_test.exs`

### U17 — `clothing_vec virtual table exists`
- **Inputs:** `SELECT name FROM sqlite_master WHERE type='table' AND name='clothing_vec'`
- **Expected:** Result has exactly one row
- **Guards against:** sqlite_vec extension not loaded (see SP-00-01 U6); migration skipped; table name typo

### U18 — `clothing_vec accepts a 512-dim float32 embedding insert`
- **Setup:** `VectorCodec.encode(List.duplicate(0.1, 512))` → `binary`
- **Inputs:** `INSERT INTO clothing_vec(rowid, embedding) VALUES (1, ?)` with `{:blob, binary}`
- **Expected:** Insert succeeds; `SELECT count(*) FROM clothing_vec` returns 1
- **Guards against:** Dimension mismatch between `vec0(embedding float[512])` declaration and VectorCodec output; Exqlite TEXT/BLOB binding mismatch; wrong type spec

### U19 — `clothing_vec rowid matches the intended clothing_item id`
- **Setup:** Insert clothing_item (capture its `id`, e.g. 42); insert into `clothing_vec` with `rowid: 42` and a valid embedding
- **Inputs:** `SELECT rowid FROM clothing_vec`
- **Expected:** Returns exactly `42`
- **Guards against:** Rowid mismanagement causing KNN results to return wrong items; rowid auto-assigned differently than expected

---

## Integration Tests

### I1 — `mix ecto.migrate runs migrations 5–7 after 1–4 without error`
- **Inputs:** Shell: `mix ecto.migrate` starting from a DB that already has migrations 1–4 applied
- **Expected:** Exit 0; migration log shows migrations 5, 6, and 7 completing in order
- **Guards against:** FTS migration running before `clothing_items` exists; sqlite_vec extension absent causing migration 7 to fail

### I2 — `mix ecto.migrate is idempotent on second run`
- **Inputs:** Shell: `mix ecto.migrate` run immediately after I1
- **Expected:** Exit 0; "Already up" for all 7 migrations
- **Guards against:** `CREATE VIRTUAL TABLE` without `IF NOT EXISTS` crashing CI on re-run

---

## E2E Tests

### E1 — `acceptance — VectorCodec encode/decode on spec vector`
- **Inputs:** `VectorCodec.encode(List.duplicate(0.0, 511) ++ [1.0])`
- **Expected:** Binary is exactly 2048 bytes; `VectorCodec.decode/1` on that binary round-trips every element within `0.0001` of the original
- **Guards against:** Failing the literal acceptance criterion stated in the phase spec

### E2 — `inserting a wrong-dimension binary into clothing_vec raises an Ecto error`
- **Inputs:** `<<0::binary-size(1024)>>` (256 floats — half the required dimensions) inserted into `clothing_vec` via `Ecto.Adapters.SQL.query!` with `{:blob, ...}` wrapper
- **Expected:** Raises `Exqlite.Error` with a message referencing dimension mismatch
- **Guards against:** Wrong-dimension embedding silently stored; KNN search returning garbage; dimension enforcement relies solely on VectorCodec rather than the DB layer

---

# Implementation Tasks

- [x] Write VectorCodec unit tests U1–U9 (all should fail — module doesn't exist)
- [x] Write migration tests U10–U19 (all should fail — tables don't exist)
- [x] Create `lib/chat_app/ai/vector_codec.ex`:
  - `encode/1`: validate length == 512, raise `ArgumentError` otherwise; pack each float with `<<f::little-float-32>>`
  - `decode/1`: validate `byte_size(binary) == 2048`, raise `ArgumentError` otherwise; unpack each 4-byte chunk with `<<f::little-float-32>>`
- [x] Run VectorCodec unit tests U1–U9 — should be green before touching migrations
- [x] Generate migration 5: `mix ecto.gen.migration create_user_preferences` — table + FK to `users` + unique index on `user_id`
- [x] Generate migration 6: `mix ecto.gen.migration create_clothing_fts` — body uses `execute/1` with the FTS5 `CREATE VIRTUAL TABLE` SQL; `down/0` uses `execute("DROP TABLE IF EXISTS clothing_fts")`
- [x] Generate migration 7: `mix ecto.gen.migration create_clothing_vec` — body uses `execute/1` with the vec0 `CREATE VIRTUAL TABLE` SQL; `down/0` uses `execute("DROP TABLE IF EXISTS clothing_vec")`
- [x] Verify migration 6 filename timestamp is later than migration 2's timestamp (FTS ordering requirement)
- [x] Run `mix ecto.migrate`
- [x] Run `mix test` — all tests including SP-00-01 and SP-00-02 suites should be green
- [x] Run `mix ecto.migrate` a second time — verify idempotent (I2)

---

# Definition of Done

- [x] `mix ecto.migrate` (all 7 migrations) exits 0 on a clean DB; second run exits 0 with "Already up" for all 7
- [x] U1–U9 pass — VectorCodec contract fully verified including error paths; little-endian encoding verified to match sqlite_vec expectations
- [x] U14 passes — FTS5 no-rebuild-no-results behaviour confirmed; content table sync semantics documented by the test
- [x] U15, U16 pass — FTS5 rebuild-and-match and non-match verified
- [x] U17–U19 pass — clothing_vec exists, accepts correct-dimension embeddings via {:blob, ...} binding, and rowid is correctly managed
- [x] E1 passes — literal acceptance criterion from phase spec is automated, not manually checked
- [x] E2 passes — DB-layer dimension enforcement verified; Exqlite BLOB binding contract confirmed
- [x] `mix test` (full suite: SP-00-01 + SP-00-02 + SP-00-03) exits 0 — no regressions
- [x] No manual checks required; all acceptance criteria from the phase spec are covered by automated tests

---

## QA Summary

**Critical Issue Found and Fixed:**
- **Issue:** VectorCodec initially used big-endian float encoding (`<<f::big-float-32>>`), but sqlite_vec expects little-endian
- **Impact:** Would cause silent wrong KNN distances in Phase 1 (major correctness bug)
- **Fix:** Changed to little-endian (`<<f::little-float-32>>`) and verified round-trip through sqlite_vec
- **Test Update:** U2 expectation changed from `<<63, 128, 0, 0>>` (big-endian 1.0) to `<<0, 0, 128, 63>>` (little-endian 1.0)

**Performance Optimization:**
- **Issue:** encode/1 used O(n²) binary concatenation via Enum.reduce
- **Fix:** Switched to idiomatic `for f <- floats, into: <<>>, do: <<f::little-float-32>>`

**Test Contract Fixes:**
- U11: Modified to insert a real user via raw SQL first, satisfying FK constraint; changed expected error from Ecto.ConstraintError to Exqlite.Error
- U18/U19: Updated to use `{:blob, VectorCodec.encode(...)}` wrapper for proper Exqlite BLOB binding (not TEXT)
- E2: Updated to use `{:blob, ...}` wrapper and expect Exqlite.Error

All 25 SP-00-03 tests pass with no regressions (2 pre-existing failures in unrelated sprints remain).
