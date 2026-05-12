---
id: SP-02-04
phase: 2
slug: fts5-index
status: complete
created: 2026-05-11
activated_date: 2026-05-12
completed_date: 2026-05-12
depends_on: []
estimated_days: 1.5
---

# SP-02-04 — FTS5Index

**Goal:** Implement `FTS5Index` with upsert and BM25-ranked search against the `clothing_fts` virtual table, including correct sort polarity, FTS5 query escaping, and the external content table upsert pattern.

---

## Scope

### In

- `lib/chat_app/search/fts5_index.ex` — `upsert/1` and `search/2`
- FTS5 query escaping (delegate to `QueryProcessor.escape_fts_query/1` — SP-02-02 is complete; do not duplicate)
- Tests against `clothing_fts` virtual table (migrated in Phase 0)

### Out

- VectorStore, HybridEngine, QueryProcessor (other search modules)
- EmbedWorker integration (EmbedWorker calls `FTS5Index.upsert/1`; that call was implemented in SP-01-07)

---

## Critical: External Content Table Upsert Pattern

`clothing_fts` was created with `content='clothing_items', content_rowid='id'`:

```sql
CREATE VIRTUAL TABLE clothing_fts USING fts5(
  title,
  content='clothing_items',
  content_rowid='id'
)
```

**Implication:** SQLite FTS5 does not store `title` data inside the FTS table. The index is maintained manually. `INSERT OR REPLACE` does **not** update an existing FTS entry — it appends a second entry for the same rowid, corrupting BM25 scores and producing duplicate results.

**Correct upsert pattern:**

```sql
-- Step 1: delete old FTS entry (must provide current title for internal bookkeeping)
INSERT INTO clothing_fts(clothing_fts, rowid, title) VALUES ('delete', ?, ?);
-- Step 2: insert new FTS entry
INSERT INTO clothing_fts(rowid, title) VALUES (?, ?);
```

This is a two-statement operation. Both must succeed atomically (wrap in a transaction).

**Only `title` is indexed.** The migration indexes only one column. `brand` and `description` are not searchable via FTS5. Any test expecting brand or description search to return results will fail.

**BM25 score polarity:** FTS5 `bm25()` returns **negative floats**. More negative = more relevant. The `ORDER BY score ASC` in the spec is correct — it places the most relevant (most negative) result first. This is the opposite of intuition and easy to invert silently.

---

## `escape_fts_query/1` Contract (Settled in SP-02-02)

`FTS5Index` delegates escaping to `QueryProcessor.escape_fts_query/1`. The contract is:

- Single quotes are **stripped** (`men's` → `mens`). SQL injection is impossible because `search/2` uses bound parameters; apostrophes are meaningless in FTS5 token matching.
- All hyphens are **stripped** — infix (`pre-owned` → `preowned`), leading (`-jacket` → `jacket`), and trailing (`jacket-` → `jacket`).
- Clean alphanumeric input is returned unchanged.

The T-01/T-02/T-03 unit tests below verify this delegated behaviour.

### No Double-Escaping: `search/2` Must Not Call `escape_fts_query/1`

`FTS5Index.search/2` must **not** call `escape_fts_query/1` internally. The caller is always responsible for escaping before calling `search/2`. Reasons:

- The `HybridEngine` path (SP-02-05a) calls `QueryProcessor.process(query_text)`, which escapes per-token, then passes the result directly to `FTS5Index.search/2`. If `search/2` called `escape_fts_query` again on the assembled string, it would strip hyphens from synonym values (`second-hand` → `secondhand`, `pre-owned` → `preowned`) that `process/1` deliberately injected verbatim into OR groups.
- Tests that call `search/2` directly with raw user input must pre-escape: `input |> QueryProcessor.escape_fts_query() |> FTS5Index.search(n)`. The I-07 test follows this pattern.

---

## Tests

> **All tests except the escape helper unit tests require `DataCase` (DB sandbox).**
> **FTS5 is DB-bound; there is no pure-function layer beyond the escape helper.**

### Unit

#### T-01 — `escape_fts_query/1` strips single quotes

- Inputs: `"men's jacket"`
- Expected: `"mens jacket"` — apostrophe stripped entirely
- Rationale: `search/2` uses bound parameters (no SQL injection risk); apostrophes have no meaning in FTS5 token matching; contract established in SP-02-02 Decision 6.
- Failure guarded: bare single quote in MATCH operand causing FTS5 syntax error

#### T-02 — `escape_fts_query/1` makes hyphenated terms safe

- Inputs: `"pre-owned"`
- Expected: `"preowned"` — hyphen stripped
- Failure guarded: FTS5 treating `-` as NOT operator, silently excluding all items matching "owned"

#### T-03 — `escape_fts_query/1` is a no-op for clean alphanumeric input

- Inputs: `"levi denim jacket"`
- Expected: output is identical to input
- Failure guarded: unnecessary mutation breaking valid query terms

### Integration (DB-bound)

#### I-01 — `upsert/1` creates a searchable FTS entry for a new item by title

- Setup: insert `%Item{title: "Vintage Levi Denim Jacket", price: "25.00", url: "http://e.com/1", source: "ebay"}` via `Repo.insert!`
- Inputs: `FTS5Index.upsert(item.id)`
- Expected: `search("levi", 5)` returns a list containing `{item.id, score}` where `score < 0`
- Failure guarded: item inserted in DB but invisible to FTS5 search

#### I-02 — `upsert/1` replaces (not duplicates) an existing FTS entry after title change

- Setup: insert item with `title: "Blue Jacket"`; `FTS5Index.upsert(item.id)`; update item title to `"Red Jacket"` in DB; `FTS5Index.upsert(item.id)` again
- Expected:
  - `search("red jacket", 5)` returns `[{item.id, _}]`
  - `search("blue jacket", 5)` returns `[]`
  - `search("red jacket", 10)` returns **exactly one** result for `item.id` (not two — confirms no duplicate FTS entry)
- Failure guarded: external content table upsert appending instead of replacing; stale FTS data; inflated BM25 scores from duplicate entries

#### I-03 — `upsert/1` for a non-existent item_id returns `:ok` without crashing

- Inputs: `FTS5Index.upsert(999_999)` (no such row in `clothing_items`)
- Expected: `:ok` — graceful no-op
- Failure guarded: EmbedWorker crashing on `Repo.get!` when an item is deleted between job scheduling and execution

#### I-04 — BM25 scores are negative floats; most relevant item appears first (ASC sort)

- Setup: insert `%Item{title: "Levi Denim Jacket", ...}` (item 1) and `%Item{title: "Silk Evening Dress", ...}` (item 2); `FTS5Index.upsert(1)`, `FTS5Index.upsert(2)`
- Inputs: `FTS5Index.search("levi denim", 10)`
- Expected:
  - Result list starts with item 1
  - `score_1 < 0` (negative float)
  - `score_2 < 0` (if item 2 appears at all; it should not match "levi denim" but may appear with a very low score)
  - `score_1 < score_2` (item 1's score is more negative — more relevant — than item 2's)
- Failure guarded: DESC sort returning worst match first; positive scores indicating BM25 sign flipped; item 2 appearing before item 1

#### I-05 — `search/2` returns `[]` for a query with no matching items

- Setup: insert item with title "Nike Running Shorts"; upsert
- Inputs: `search("xyzzy plugh", 10)`
- Expected: `[]`
- Failure guarded: crash or exception on zero-match FTS5 MATCH query

#### I-06 — `search/2` respects `top_n`

- Setup: insert and upsert 10 items all with titles containing "jacket"
- Inputs: `search("jacket", 3)`
- Expected: `length(result) == 3`
- Failure guarded: LIMIT clause ignored; all matching rows returned

#### I-07 — `search/2` with apostrophe in query returns matching item without crashing

- Setup: insert `%Item{title: "Mens Leather Jacket", ...}`; `FTS5Index.upsert(item.id)`
- Inputs: `"men's jacket" |> QueryProcessor.escape_fts_query() |> FTS5Index.search(5)`
- Expected: result contains `{item.id, score}` where `score < 0`; no exception raised; no DB error
- Note: caller escapes before `search/2` — required pattern per no-double-escaping contract. Item title uses "Mens" (no apostrophe) so it indexes as token `mens`, matching the escaped query.
- Failure guarded: unescaped apostrophe in MATCH operand causing FTS5 syntax error

#### I-08 — `search/2` with empty query string returns `[]` without crashing

- Inputs: `search("", 10)` (no DB setup required)
- Expected: `[]`
- Failure guarded: empty MATCH expression causing FTS5 syntax error

#### I-09 — `upsert/1` for an item with empty string title does not crash

- Setup: insert item with `title: ""`, all required fields present
- Inputs: `FTS5Index.upsert(item.id)`
- Expected: `:ok`; `search("", 5)` returns `[]`; no DB error
- Failure guarded: empty title causing FTS5 write to fail, bringing down EmbedWorker for any item with missing title data

#### I-10 — FTS5 operator words in query do not cause a parse error

- Setup: insert and upsert one item with title "Leather Jacket"
- Inputs: `search("NOT jacket", 5)`, `search("OR dress", 5)`, `search("AND coat", 5)` (each called independently)
- Expected: each call returns a list (possibly empty) — no exception, no DB error raised
- Failure guarded: FTS5 interpreting NOT/OR/AND as operators, producing inverted results or crashing

#### I-11 — `search/2` by brand or description returns `[]` (only title is indexed)

- Setup: insert item with `title: "Plain Shirt"`, `brand: "Levi"`, `description: "denim jacket style"`; upsert
- Inputs: `search("levi", 5)`, `search("denim jacket style", 5)`
- Expected: both return `[]` — brand and description are not in the FTS5 index
- Failure guarded: implementer accidentally indexing additional fields, silently changing the contract; or tests passing against a wider schema that production doesn't have

### E2E

#### E-01 — Positive: insert item, upsert FTS, search by title keyword — item appears first

- Setup: insert three items — "Vintage Levi Denim Jacket", "Nike Running Shorts", "Silk Evening Dress"; upsert all three
- Inputs: `search("levi denim jacket", 3)`
- Expected: first result is the Levi jacket's item_id; its score is the most negative of all returned scores
- Failure guarded: end-to-end FTS5 pipeline broken at any layer

#### E-02 — Negative: queries with only FTS5 metacharacters return `[]` without exception

- Inputs: `search("", 5)`, `search("()", 5)`, `search("*", 5)` (each independently; note bare `'''` becomes `""` after escape, so use the empty-string form)
- Expected: each returns `[]` — no unhandled exception, no DB connection left in error state
- Failure guarded: malformed MATCH query crashing the DB connection for subsequent queries in the same process

#### E-03 — Negative: orphaned FTS entry after item deletion — search does not crash

- Setup: insert item, upsert FTS, then delete the `clothing_items` row without cleaning up the FTS table
- Inputs: `search("jacket", 5)`
- Expected: returns `[{item_id, score}]` or `[]` — no crash; note this tests that the FTS index survives a missing content row (rowid is still in FTS index; content table lookup is not performed for rowid/score-only queries)
- Failure guarded: assumption that FTS5 auto-validates against content table on search, causing crashes when content rows are deleted

---

## Implementation Tasks

- [x] Write unit tests T-01, T-02, T-03 (escape helper) — all fail
- [x] Write integration tests I-01 through I-11 — all fail
- [x] Write E2E tests E-01, E-02, E-03 — all fail
- [x] Create `lib/chat_app/search/fts5_index.ex`
- [x] Implement `escape_fts_query/1` by delegating to `QueryProcessor.escape_fts_query/1`
- [x] Run escape unit tests — green
- [x] Implement `upsert/1`:
  - [x] `Repo.get(Item, item_id)` — return `:ok` immediately if nil (graceful no-op)
  - [x] Wrap both SQL statements in a `Repo.transaction/1`:
    - [x] `INSERT INTO clothing_fts(clothing_fts, rowid, title) VALUES ('delete', ?, ?)` with current title
    - [x] `INSERT INTO clothing_fts(rowid, title) VALUES (?, ?)` with new title
  - [x] Return `:ok`
- [x] Implement `search/2`:
  - [x] Guard: return `[]` immediately if `query_text` is empty string
  - [x] Do NOT call `escape_fts_query/1` — the caller is responsible (see no-double-escaping contract above)
  - [x] Execute `SELECT rowid, bm25(clothing_fts) AS score FROM clothing_fts WHERE clothing_fts MATCH ? ORDER BY score ASC LIMIT ?`
  - [x] Return `[{rowid, score}]` as `[{integer(), float()}]`
- [x] Run all integration and E2E tests — all green

---

## Definition of Done

- [x] All 17 tests green (`mix test test/integration/search/fts5_index_test.exs`)
- [x] BM25 sort polarity explicitly verified: I-04 green with score negative and item 1 before item 2
- [x] Upsert idempotency confirmed: I-02 green with exactly one result after two upserts for the same item
- [x] `search("")` returns `[]` and does not raise (I-08 green)
- [x] `upsert/1` for non-existent item returns `:ok` (I-03 green)
- [x] External content table delete-then-insert pattern used (not INSERT OR REPLACE): verified by I-02 returning single result
- [x] `search/2` does not call `escape_fts_query/1` internally — no double-escape regression
