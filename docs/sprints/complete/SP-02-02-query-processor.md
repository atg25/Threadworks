---
id: SP-02-02
phase: 2
slug: query-processor
status: complete
created: 2026-05-11
activated_date: 2026-05-11
completed_date: 2026-05-11
depends_on: []
estimated_days: 1
---

# SP-02-02 — QueryProcessor

**Goal:** Implement a pure-function text processor that lowercases, strips English stopwords (preserving clothing size terms), normalizes whitespace, expands synonyms with OR semantics, and escapes FTS5 MATCH metacharacters.

---

## Scope

### In
- `lib/chat_app/search/query_processor.ex` — `process/1` and `escape_fts_query/1`
- Stopword list (English common words, excluding all clothing size terms)
- Synonym map (exactly as specced)
- Whitespace normalization
- FTS5 MATCH metacharacter escaping

### Out
- Any DB interaction — this module is pure functions only
- FTS5Index, VectorStore, HybridEngine (consumers)
- Vector search path (raw query is passed to Embedder unchanged)

---

## Design Decisions

**Decision 1 — Synonym expansion is additive (original term preserved)**
`"thrifted jacket"` → the word `"thrifted"` is preserved alongside its synonyms. Rationale: the original term may itself be indexed (e.g. item description says "thrifted"), and replacement-only would lose that signal.

**Decision 2 — Synonym groups use lowercase `or` grouping syntax**
Expanded synonyms are wrapped in parentheses with lowercase `or`: `thrifted → (thrifted or second-hand or pre-owned or vintage)`. Lowercase is consistent with the pipeline's all-lowercase output (Decision 5). FTS5 accepts case-insensitive operators.

**Decision 3 — FTS5 operator words (AND, OR, NOT, NEAR) are wrapped in double-quotes**
When these appear as bare tokens after lowercasing, wrap them: `not → "not"`. This prevents FTS5 from interpreting them as query operators. These words are NOT in the stopword list — they are quoted instead of stripped so users can still search for items described with these words.

**Decision 4 — Whitespace normalization: collapse to single spaces, trim**
Multiple consecutive spaces, tabs, and leading/trailing whitespace are reduced to a single space between tokens.

**Decision 5 — All output is lowercase; no uppercase characters anywhere**
`process/1` lowercases the entire query first. OR group connectors use lowercase `or` for consistency. This is the invariant checked by T-01 and E-01.

**Decision 6 — `escape_fts_query/1` strips apostrophes and bare hyphens; it is NOT a SQL escaper**
`QueryProcessor` is not responsible for SQL-level escaping. Its `escape_fts_query/1` function:

- Strips single quotes entirely (`men's` → `mens`). Apostrophes have no useful meaning in FTS5 token search.
- Strips bare hyphens between word characters (`pre-owned` → `preowned`). FTS5 interprets `-` as a NOT operator at the query level.

SQL-level apostrophe escaping (`'` → `''`) is the responsibility of `FTS5Index`, which calls `escape_fts_query/1` and then passes the result as a bound parameter (making SQL injection impossible). See SP-02-04 for the `FTS5Index` contract.

**Decision 7 — `escape_fts_query/1` is called per user input token, not on the final assembled string**
`process/1` pipeline: lowercase → tokenize → escape each token → remove stopwords → synonym expand (synonyms injected verbatim with hyphens) → FTS5 operator quoting → rejoin → trim. Applying `escape_fts_query` last on the fully-assembled OR-group string would corrupt the hyphenated synonym terms that T-04/T-05 require.

---

## Tests

> **No DB required. All tests are pure function calls.**

### Unit

**T-01 — `process/1` lowercases the query**
- Inputs: `"Vintage LEVI Denim"`
- Expected: all characters in output are lowercase (no uppercase letters)
- Failure guarded: case-sensitive FTS miss — "LEVI" not matching "levi" in index

**T-02 — `process/1` removes common English stopwords**
- Inputs: `"the a vintage jacket"`
- Expected: output does not contain standalone tokens `"the"` or `"a"`; does contain `"vintage"` and `"jacket"`
- Failure guarded: noise words inflating FTS query, reducing BM25 precision

**T-03 — `process/1` preserves all nine clothing size terms**
- Inputs: `"xs s m l xl xxl small medium large jacket"`
- Expected: all nine size tokens are present in output: `xs`, `s`, `m`, `l`, `xl`, `xxl`, `small`, `medium`, `large`
- Failure guarded: size terms stripped by an overly broad stopword list, making size-based search impossible

**T-04 — `process/1` expands "thrifted" additively — original term and all three synonyms present**
- Inputs: `"thrifted jacket"`
- Expected: output contains `"thrifted"`, `"second-hand"`, `"pre-owned"`, `"vintage"` (all four, not just the synonyms)
- Failure guarded: original term lost, items literally described as "thrifted" in the index not returned

**T-05 — `process/1` expansion uses OR grouping syntax**
- Inputs: `"thrifted jacket"`
- Expected: output contains the substring `"(thrifted or second-hand or pre-owned or vintage)"` (lowercase `or`)
- Failure guarded: AND-joined synonyms requiring all four to co-occur in one item, producing zero results

**T-06 — `process/1` expands "preloved"**
- Inputs: `"preloved coat"`
- Expected: output contains `"preloved"`, `"pre-owned"`, `"second-hand"` within a single OR group
- Failure guarded: near-synonym for thrifted not handled, missing indexed items

**T-07 — `process/1` expands "y2k"**
- Inputs: `"y2k top"`
- Expected: output contains `"y2k"`, `"2000s"`, `"early 2000s"` within a single OR group
- Failure guarded: decade-style query returning zero results because item descriptions use "2000s" not "y2k"

**T-08 — `process/1` expands "streetwear"**
- Inputs: `"streetwear pants"`
- Expected: output contains `"streetwear"`, `"urban"`, `"hypebeast"` within a single OR group
- Failure guarded: subculture style terms missing alternatives indexed under different labels

**T-09 — `process/1` expands "preppy"**
- Inputs: `"preppy blazer"`
- Expected: output contains `"preppy"`, `"ivy league"`, `"nautical"` within a single OR group
- Failure guarded: preppy style search misses items tagged "nautical" or "ivy league"

**T-10 — `process/1` passes unknown terms through unchanged**
- Inputs: `"zardigan mesh corset"`
- Expected: all three tokens present in output (lowercased), no crash, no synonym expansion applied
- Failure guarded: crash or silent drop of words not in synonym map

**T-11 — `process/1` handles empty string**
- Inputs: `""`
- Expected: `""`
- Failure guarded: crash on empty input; garbage tokens returned

**T-12 — `process/1` normalizes whitespace**
- Inputs: `"  vintage   jacket  "` (leading spaces, trailing spaces, double internal space)
- Expected: output is `"vintage jacket"` (or equivalent with no leading/trailing/double whitespace)
- Failure guarded: extra whitespace producing malformed FTS5 MATCH clause

**T-13 — `process/1` wraps FTS5 operator tokens in double-quotes**
- Inputs: `"NOT jacket"`, `"OR dress"`, `"AND coat"`, `"NEAR boots"`
- Expected: `"not"`, `"or"`, `"and"`, `"near"` are each wrapped as `"\"not\""`, `"\"or\""` etc. — not left as bare uppercase or lowercase operator tokens
- Failure guarded: FTS5 interpreting user-supplied words as query operators, inverting or breaking search results

**T-14 — `escape_fts_query/1` strips single quotes**
- Inputs: `"men's jacket"`
- Expected: `"mens jacket"` — apostrophe removed entirely
- Rationale: `QueryProcessor` is not a SQL escaper. SQL-level quoting is the DB layer's concern. Apostrophes are meaningless in FTS5 token matching. See Decision 6.
- Failure guarded: bare single quote passed through to FTS5 MATCH clause at runtime

**T-15 — `escape_fts_query/1` makes hyphenated terms safe**
- Inputs: `"pre-owned"`
- Expected: resulting string does not contain a bare hyphen between word characters (`preowned`)
- Failure guarded: FTS5 treating `-` as NOT operator, producing results that exclude "owned" items

**T-16 — `escape_fts_query/1` is a no-op for clean alphanumeric queries**
- Inputs: `"levi denim jacket"`
- Expected: output is identical to input (or logically equivalent — no mutation of clean tokens)
- Failure guarded: unnecessary transformation corrupting valid query terms

### E2E

**E-01 — Positive: full pipeline on a realistic multi-term query**
- Inputs: `"Thrifted Y2K Streetwear L Jacket"`
- Expected:
  - All characters lowercase (including OR group connectors, which use lowercase `or`)
  - `"l"` preserved (size term, not stopword)
  - `"jacket"` present
  - `"thrifted"`, `"second-hand"`, `"pre-owned"`, `"vintage"` all present in an OR group
  - `"y2k"`, `"2000s"`, `"early 2000s"` all present in an OR group
  - `"streetwear"`, `"urban"`, `"hypebeast"` all present in an OR group
  - No uppercase characters anywhere in output
- Failure guarded: any pipeline stage silently dropping terms or failing to lowercase

**E-02 — Negative: query composed entirely of stopwords returns empty string**
- Inputs: `"the a an in of"`
- Expected: `""` exactly
- Failure guarded: empty MATCH clause forwarded to FTS5, causing syntax error; or non-empty output with only stopword tokens that FTS5 cannot match meaningfully

**E-03 — Negative: query with apostrophes and hyphens produces no single quotes in output**
- Inputs: `"men's pre-owned y2k jacket"`
- Expected: `String.contains?(result, "'")` is `false` — apostrophe stripped by `escape_fts_query/1`
- Failure guarded: bare single quote passed to FTS5 MATCH causing a syntax error

---

## Implementation Tasks

- [x] Create `lib/chat_app/search/` directory
- [x] Write all unit tests (T-01 through T-16) — all fail
- [x] Write E2E tests (E-01, E-02, E-03) — all fail
- [x] Implement `process/1`:
  - [x] Lowercase
  - [x] Tokenize on whitespace
  - [x] Escape each token via `escape_fts_query/1` (per-token, not on final string — see Decision 7)
  - [x] Remove stopwords, preserving size terms (`xs s m l xl xxl small medium large`)
  - [x] Apply synonym expansion: for each token matching a synonym key, replace with OR group `"(original or syn1 or syn2 ...)"` as a single token (lowercase `or` connectors)
  - [x] Wrap bare FTS5 operator words (`and or not near`) in double-quotes
  - [x] Re-join tokens with single spaces
  - [x] Trim leading/trailing whitespace
- [x] Implement `escape_fts_query/1`:
  - [x] Strip single quotes: `String.replace(q, "'", "")`
  - [x] Strip bare hyphens: `String.replace(q, ~r/(\w)-(\w)/, "\\1\\2")`
- [x] Run all tests — all green

---

## Definition of Done

- [x] All 19 tests green (`mix test test/unit/search/query_processor_test.exs`)
- [x] `process/1` is a pure function — no side effects, no DB calls, no process spawning
- [x] `process("")` returns `""`
- [x] No `import Ecto` or database references anywhere in the module
- [x] Synonym expansion output format is OR-grouped: verified by T-05
- [x] FTS5 operator tokens handled: verified by T-13
