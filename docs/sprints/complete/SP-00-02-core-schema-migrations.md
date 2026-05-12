---
id: SP-00-02
phase: 0
status: complete
created_date: 2026-05-06
activated_date: 2026-05-06
completed_date: 2026-05-06
---

# Goal

Land the Oban jobs table, the enhanced `clothing_items` schema, `price_history`, and `saved_items` in a single idempotent migration run, with tests confirming every column and constraint before the migration files are created.

---

# Scope

**In scope:**
- Migration 1: `_add_oban_jobs_table` via `Oban.Migration.up(version: 12)`
- Migration 2: `_enhance_clothing_items` — 8 new columns + unique index on `[:source, :source_id]`
- Migration 3: `_create_price_history` — FK → `clothing_items` with CASCADE delete
- Migration 4: `_create_saved_items` — FK → `users` and `clothing_items`; unique index; `ON DELETE SET NULL` on `item_id`

**Out of scope:**
- Migrations 5–7 (user_preferences, FTS5, sqlite_vec virtual tables)
- VectorCodec module
- Ecto schema modules (changesets, contexts) — those come in the phases that use the schemas
- Any application logic that reads or writes these tables

---

# Tests

> **Critical prerequisite for all FK tests:** SQLite does not enforce foreign keys by default. Every test that exercises a FK constraint (U8, U9, U12, U13, U15) must run `Ecto.Adapters.SQL.query!(repo, "PRAGMA foreign_keys = ON", [])` in its setup block, or confirm that the project's `conn_case.ex` / Repo `:after_connect` already enables this pragma globally. Without it, FK tests will pass even if the FK definition is missing or wrong — a silent false green.

**File:** `test/chat_app/migrations/enhance_clothing_items_test.exs`

All tests query DB state directly via `PRAGMA table_info` — they do not depend on Ecto schema modules.

---

## Unit Tests

### U1 — `clothing_items has source column of type TEXT`
- **Inputs:** `PRAGMA table_info(clothing_items)` via `Ecto.Adapters.SQL.query!`
- **Expected:** Result rows include `%{name: "source", type: "TEXT"}`
- **Guards against:** Column omitted or mapped to wrong SQLite type

### U2 — `clothing_items has source_id column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "source_id"}`
- **Guards against:** Typo in column name (`sourceId`, `source_identifier`, etc.)

### U3 — `clothing_items has embedding column of type BLOB`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "embedding", type: "BLOB"}`
- **Guards against:** Embedding stored as TEXT — silently accepts binary but breaks sqlite_vec insertion

### U4 — `clothing_items has style_tags column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "style_tags"}`
- **Guards against:** JSON column omitted; scraper has nowhere to write style data

### U5 — `clothing_items has last_scraped_at column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "last_scraped_at"}`
- **Guards against:** Timestamp column omitted; scrape recency tracking impossible

### U5a — `clothing_items has color column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "color"}`
- **Guards against:** Column omitted from migration; silently missing from schema

### U5b — `clothing_items has size_normalized column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "size_normalized"}`
- **Guards against:** Column omitted; size normalization data has no storage destination

### U5c — `clothing_items has condition_normalized column`
- **Inputs:** `PRAGMA table_info(clothing_items)`
- **Expected:** Result rows include `%{name: "condition_normalized"}`
- **Guards against:** Column omitted; condition data silently dropped at insert time

### U6a — `unique index rejects duplicate source and source_id pair`
- **Inputs:** Two separate inserts with identical `source: "ebay"` and `source_id: "abc123"` into `clothing_items`
- **Expected:** Second insert raises `Ecto.ConstraintError` (unique violation)
- **Guards against:** Missing unique index; duplicate scrape records for the same listing

### U6b — `unique index allows rows with distinct source_id values`
- **Inputs:** Insert `{source: "ebay", source_id: "1"}` then `{source: "ebay", source_id: "2"}`
- **Expected:** Both inserts succeed; table contains two rows
- **Guards against:** Index written on wrong columns, blocking all inserts from the same source

### U6c — `unique index allows multiple rows with NULL source_id`
- **Inputs:** Two inserts with `source: "ebay"` and `source_id: nil`
- **Expected:** Both inserts succeed
- **Guards against:** Developer assuming NULL is deduplicated by the unique index — SQLite permits multiple NULLs; callers must handle this explicitly if deduplication of NULL rows is required

---

**File:** `test/chat_app/migrations/price_history_test.exs`

### U7 — `price_history table exists with expected columns`
- **Inputs:** `PRAGMA table_info(price_history)`
- **Expected:** Non-empty result; rows include `item_id`, `inserted_at`
- **Guards against:** Migration not run; table name typo

### U8 — `price_history FK enforced on insert with pragma on`
- **Setup:** `PRAGMA foreign_keys = ON`
- **Inputs:** Insert into `price_history` with `item_id: 99999` (no matching `clothing_items` row)
- **Expected:** Raises `Ecto.ConstraintError` (FK violation)
- **Guards against:** FK omitted from migration; pragma not set; test gives false green without pragma

### U9 — `deleting a clothing_item cascades to price_history`
- **Setup:** `PRAGMA foreign_keys = ON`; insert clothing_item (capture id); insert price_history row referencing that id
- **Inputs:** Delete the clothing_item row
- **Expected:** The price_history row is also deleted; `SELECT count(*) FROM price_history WHERE item_id = <id>` returns 0
- **Guards against:** FK action set to `NO ACTION` instead of `CASCADE`; orphaned price history rows accumulate

---

**File:** `test/chat_app/migrations/saved_items_test.exs`

### U10 — `saved_items table exists with all expected columns`
- **Inputs:** `PRAGMA table_info(saved_items)`
- **Expected:** Rows for `user_id`, `item_id`, `price_at_save`, `notes`, `inserted_at`
- **Guards against:** Any column omitted from migration

### U11 — `unique index prevents duplicate user and item pair`
- **Setup:** `PRAGMA foreign_keys = ON`; valid user and clothing_item exist
- **Inputs:** Insert `{user_id: uid, item_id: iid}` twice
- **Expected:** Second insert raises `Ecto.ConstraintError` (unique violation)
- **Guards against:** Missing unique index; user can save same item multiple times

### U12 — `deleting a clothing_item sets saved_items.item_id to NULL`
- **Setup:** `PRAGMA foreign_keys = ON`; insert clothing_item (id=X); insert saved_item with `item_id: X`
- **Inputs:** Delete the clothing_item
- **Expected:** The saved_item row still exists; `item_id` is `nil`; `SELECT count(*) FROM saved_items WHERE id = <saved_item_id>` returns 1
- **Guards against:** `ON DELETE CASCADE` silently destroying saved history; `ON DELETE RESTRICT` blocking clothing_item deletion; `ON DELETE NO ACTION` leaving a dangling FK

### U13 — `saved_items.item_id accepts NULL on direct insert`
- **Inputs:** Insert saved_item with `item_id: nil`, valid `user_id`
- **Expected:** Insert succeeds
- **Guards against:** `NOT NULL` constraint on `item_id` blocking the "Listing Removed" sentinel state

### U14 — `saved_items user_id FK enforced with pragma on`
- **Setup:** `PRAGMA foreign_keys = ON`
- **Inputs:** Insert saved_item with `user_id: 99999` (no matching user)
- **Expected:** Raises `Ecto.ConstraintError`
- **Guards against:** User FK omitted; orphaned saved_item rows persist after a user account is deleted

---

## Integration Tests

### I1 — `mix ecto.migrate runs all 4 migrations without error`
- **Inputs:** Shell: `mix ecto.migrate` against a clean test database
- **Expected:** Exit code 0; migration log includes all four migration filenames
- **Guards against:** One migration silently errors and Ecto skips or partially applies it

### I2 — `mix ecto.migrate is idempotent on second run`
- **Inputs:** Shell: `mix ecto.migrate` run a second time immediately after I1
- **Expected:** Exit code 0; log shows "Already up" or equivalent for all four migrations
- **Guards against:** Non-idempotent migration DDL (e.g. `CREATE TABLE` without `IF NOT EXISTS`) crashing CI on re-run

---

## E2E Tests

### E1 — `happy path — Oban jobs table accepts a job insert`
- **Inputs:** In a test using `Oban.Testing`, enqueue a minimal worker job
- **Expected:** Job row appears in `oban_jobs`; no exception raised
- **Guards against:** `Oban.Migration.up(version: 12)` version mismatch with installed Oban version, producing an incomplete or incompatible jobs table schema

### E2 — `inserting a clothing_item without source raises a constraint error`
- **Inputs:** Attempt to insert a clothing_item with `source: nil`
- **Expected:** Raises `Ecto.ConstraintError` (NOT NULL violation) if the column is defined NOT NULL, or succeeds if nullable — document the decision
- **Note:** The spec lists `source` as `"ebay"`, `"depop"`, or `"poshmark"` with no NULL case. The migration should enforce NOT NULL. This test confirms the decision. If the test passes with nil, the migration is under-constrained.
- **Guards against:** Ambiguity between spec intent and migration DDL

---

# Implementation Tasks

- [x] Write unit tests U1–U14 and E2E tests E1–E2 (all should fail — tables don't exist yet)
- [x] Confirm `conn_case.ex` or Repo config enables `PRAGMA foreign_keys = ON`; if not, add explicit pragma to each FK test setup — added to each FK test module's `setup` block
- [x] Generate migration 1: `mix ecto.gen.migration add_oban_jobs_table` — satisfied by existing `20260516000000_add_oban.exs` (`Oban.Migrations.up()` creates version-12-compatible schema; E1 passes)
- [x] Generate migration 2: `mix ecto.gen.migration enhance_clothing_items` — adds source (NOT NULL), source_id, style_tags, color, size_normalized, condition_normalized, last_scraped_at; unique index on [:source, :source_id]
- [x] Generate migration 3: `mix ecto.gen.migration create_price_history` — table with FK → clothing_items ON DELETE CASCADE
- [x] Generate migration 4: `mix ecto.gen.migration create_saved_items` — FK → users (NOT NULL, ON DELETE CASCADE), FK → clothing_items (nilify_all / ON DELETE SET NULL), unique index on [:user_id, :item_id]
- [x] Run `mix ecto.migrate`
- [x] Run `mix test` — verify U1–U14, E1–E2 pass — 23/23 green
- [x] Run `mix ecto.migrate` a second time — verify I2 (no-op) — no migrations ran

---

# Definition of Done

- [ ] `mix ecto.migrate` exits 0 on a clean DB; second run exits 0 with no migrations applied
- [ ] U1–U14 all pass — including U5a, U5b, U5c (all 8 spec columns verified)
- [ ] U6a, U6b, U6c all pass — unique index constraint and NULL semantics both confirmed
- [ ] U8, U9, U12, U14 all pass with `PRAGMA foreign_keys = ON` active — FK behaviour verified, not assumed
- [ ] U12 confirmed: saved_item row survives clothing_item deletion with `item_id = nil`
- [ ] E1, E2 pass
- [ ] `mix test` (full suite including SP-00-01 tests) exits 0 — no regressions
