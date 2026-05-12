---
status: draft
last_updated: 2026-05-06
phase: 4
sub_phase: 2
slug: hybrid-search
complexity: M
---

# Phase 2 — Hybrid Search

**Goal:** Build a vector + keyword search engine over `clothing_items` that returns RRF-ranked results for a natural language query.

---

## Deliverables

### `lib/chat_app/ai/embedder.ex`

- `embed(text :: String.t()) :: {:ok, [float()]} | {:error, term()}`
- `embed_batch(texts :: [String.t()]) :: {:ok, [[float()]]} | {:error, term()}`
- POST `https://api.openai.com/v1/embeddings`, model `text-embedding-3-small`, `dimensions: 512`
- L2-normalize each vector before returning: `v / sqrt(sum(v_i^2))`
- Used for both item indexing (Phase 1 EmbedWorker) and query embedding (Phase 2 HybridEngine)

### `lib/chat_app/search/vector_store.ex`

- `upsert(item_id :: integer(), vector :: [float()]) :: :ok` — inserts or replaces into `clothing_vec` using VectorCodec-encoded binary
- `search(query_vector :: [float()], top_n :: integer()) :: [{integer(), float()}]` — returns `[{item_id, distance}]` sorted ASC by distance (closest = most similar = first)

Query:
```sql
SELECT rowid, distance
FROM clothing_vec
WHERE embedding MATCH ?
ORDER BY distance
LIMIT ?
```

### `lib/chat_app/search/fts5_index.ex`

- `upsert(item_id :: integer()) :: :ok` — rebuilds FTS5 entry for one item by fetching current field values from `clothing_items`; called by EmbedWorker (explicit sync, no triggers)
- `search(query_text :: String.t(), top_n :: integer()) :: [{integer(), float()}]` — returns `[{item_id, bm25_score}]` sorted ASC (most-negative score = most relevant = first)

**Important:** SQLite FTS5 `bm25()` returns negative floats. More negative = more relevant. Sort direction is ASC, not DESC.

Query:
```sql
SELECT rowid, bm25(clothing_fts) AS score
FROM clothing_fts
WHERE clothing_fts MATCH ?
ORDER BY score ASC
LIMIT ?
```

Escape special characters in `query_text` before passing to MATCH (apostrophes → `''`, strip hyphens or wrap in double-quotes).

### `lib/chat_app/search/query_processor.ex`

Steps applied to query before FTS5 search (vector search uses the raw query):

1. Lowercase
2. Remove English stopwords — **exclude** size terms: `xs`, `s`, `m`, `l`, `xl`, `xxl`, `small`, `medium`, `large` (these are meaningful for clothing)
3. Synonym expansion:

```elixir
@synonyms %{
  "thrifted"  => ["second-hand", "pre-owned", "vintage"],
  "preloved"  => ["pre-owned", "second-hand"],
  "y2k"       => ["y2k", "2000s", "early 2000s"],
  "streetwear" => ["streetwear", "urban", "hypebeast"],
  "preppy"    => ["preppy", "ivy league", "nautical"]
}
```

Returns a processed query string for FTS5 MATCH.

### `lib/chat_app/search/hybrid_engine.ex`

`search(query_text, opts \\ []) :: {:ok, [%ClothingItem{}]} | {:error, term()}`

opts keys: `source: :ebay | :depop | :poshmark | nil`, `max_price: Decimal.t() | nil`, `size: String.t() | nil`, `limit: integer() \\ 10`

Steps:
1. Embed `query_text` via `Embedder.embed/1` → `query_vector`
2. Process `query_text` via `QueryProcessor.process/1` → `processed_query`
3. Run in parallel (Task.async): `VectorStore.search(query_vector, 50)` and `FTS5Index.search(processed_query, 50)`
4. Build rank maps: `%{item_id => rank}` for each pipeline (rank 1 = best)
5. RRF fusion: for each unique item_id, `score = sum(1 / (60 + rank))` across pipelines
6. Sort by RRF score DESC, take `limit` results
7. Fetch full `%ClothingItem{}` records for result item_ids from DB, apply any opt filters (source, max_price, size) as WHERE conditions in step 3 to pre-filter candidates
8. Return `{:ok, items}` where each item has a virtual `:rrf_score` field

Return `{:ok, []}` if both pipelines return empty — never raise.

### `ChatApp.Clothing.search_hybrid/2`

Public API: `search_hybrid(query_text, opts \\ [])` — delegates to `HybridEngine.search/2`.

### Test Fixtures

**`test/fixtures/embeddings.exs`** — pre-computed 512-dim float vectors for 3 test items (generated once, committed, never regenerated automatically):
- Item A: embedding close to `"vintage levi denim jacket"` query
- Item B: embedding distant from that query
- Item C: embedding close to query but title has no keyword overlap

---

## Acceptance Criteria

- **Ordering test (unit):** Seed DB with Items A, B, C from fixtures. `HybridEngine.search("vintage levi denim jacket")` returns Item A before Items B and C.
- **Empty DB (unit):** `HybridEngine.search("anything")` with empty DB returns `{:ok, []}` without error.
- **Empty query (unit):** `HybridEngine.search("")` returns `{:ok, []}` without error.
- **Embedder normalization (unit):** `{:ok, vec} = Embedder.embed("test")` — `length(vec)` = 512; `:math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))` is within 0.001 of 1.0.
- **VectorStore round-trip (unit):** `VectorStore.upsert(99, fixture_vector_a)`, then `VectorStore.search(fixture_vector_a, 5)` → first element is `{99, distance}` where `distance < 0.001`.
- **FTS5 sort polarity (unit):** Insert two items, one with title "Levi Denim Jacket" and one with "Silk Dress". `FTS5Index.search("levi denim", 10)` → first result's `bm25_score` is more negative than second; result with "Levi" appears first.
- **FTS5 upsert (unit):** `FTS5Index.upsert(item_id)` on an existing item does not raise; subsequent `FTS5Index.search` returns updated content.

---

## Dependencies

- Phase 0 complete (`clothing_vec` and `clothing_fts` virtual tables exist)
- Phase 1 complete (`FTS5Index.upsert/1` call in EmbedWorker must be implemented before search can be tested with real data)
- Pre-computed test fixture embeddings in `test/fixtures/embeddings.exs`

---

## Complexity: M

sqlite-vec and FTS5 are both novel in Elixir with limited documentation. The BM25 sort-polarity gotcha (scores are negative) is easy to get wrong silently. RRF fusion is straightforward arithmetic. The fixture-embedding workflow (generate once offline, commit) requires a one-time manual step before tests can run.

---

## Risks

- **sqlite-vec query syntax:** Pin the exact Hex version in mix.exs. The `vec0` MATCH syntax may differ between versions. Run a smoke test immediately after adding the dep.
- **FTS5 MATCH special characters:** Single-quotes and parentheses in item titles will break the MATCH query. Implement an `escape_fts_query/1` helper that wraps the query in double-quotes.
- **512-dim quality:** Run a manual recall test with 100 real items before committing to 512 dimensions. If results are poor, raise to 1536 (full model output) at 3× the storage cost.
- **Fixture embedding generation:** Embeddings must be generated with the exact same model and dimension settings used in production. Generate them once using a one-off `mix run` script and commit the output. Do not rely on live API calls in tests.
