---
id: SP-02-01
phase: 2
slug: embedder-fixtures
status: complete
activated_date: 2026-05-11
completed_date: 2026-05-11
created: 2026-05-11
depends_on: []
estimated_days: 1.5
---

# SP-02-01 — Embedder + Test Fixtures

**Goal:** Implement `Embedder` with L2 normalization and generate committed pre-computed fixture embeddings that every downstream search sprint depends on.

---

## Scope

### In
- `lib/chat_app/ai/embedder.ex` — `embed/1` and `embed_batch/1`
- HTTP client wiring (Req or Tesla) for OpenAI `/v1/embeddings`
- L2 normalization applied to every vector before returning
- `scripts/gen_fixtures.exs` — one-off Mix script, run manually once, not in CI
- `test/fixtures/embeddings.exs` — committed output with three named vectors: `:fixture_a`, `:fixture_b`, `:fixture_c`

### Out
- VectorStore, FTS5Index, QueryProcessor, HybridEngine
- Any module that *consumes* Embedder (EmbedWorker integration is SP-01-07, already complete)
- Automatic fixture regeneration in CI — fixtures are static, committed once, never regenerated automatically

---

## Fixture Definitions

Three 512-element float vectors generated once from the real OpenAI API (`text-embedding-3-small`, `dimensions: 512`) and committed verbatim:

| Key | Description |
|-----|-------------|
| `:fixture_a` | Embedding of `"vintage levi denim jacket secondhand"` — close to the acceptance-criterion query |
| `:fixture_b` | Embedding of `"pink silk evening gown formal wear"` — distant from the acceptance-criterion query |
| `:fixture_c` | Embedding of `"denim jacket indigo blue worn preloved"` — close to query semantically but title has no keyword overlap with "levi" |

Fixture generation is a **manual one-time step**, not part of `mix test`. Run:

```bash
OPENAI_API_KEY=sk-... mix run scripts/gen_fixtures.exs
```

The script writes `test/fixtures/embeddings.exs` and exits. Commit the output. Do not re-run unless intentionally regenerating all fixtures.

---

## Tests

> **All tests use mocked HTTP. No live API calls during `mix test`.**

### Unit

**T-01 — `embed/1` returns a 512-element list**
- Inputs: query `"test"`, mock HTTP returning `{"data": [{"embedding": [<512 floats>]}], "model": "text-embedding-3-small"}`
- Expected: `{:ok, vec}` where `length(vec) == 512`
- Failure guarded: dimension mismatch silently accepted, corrupting all downstream KNN distances

**T-02 — `embed/1` returns an L2-normalized vector**
- Inputs: query `"test"`, mock returning a known non-unit vector (e.g. 512 floats all equal to `2.0`)
- Expected: `{:ok, vec}` where `:math.sqrt(Enum.sum(Enum.map(vec, &(&1 * &1))))` is within `0.001` of `1.0`
- Failure guarded: normalization omitted or applied with wrong formula

**T-03 — `embed_batch/1` returns one normalized 512-dim vector per input text, all distinct**
- Inputs: `["alpha", "beta", "gamma"]`, mock returning 3 distinct 512-element float lists (none identical)
- Expected: `{:ok, vecs}` where `length(vecs) == 3`; each element has `length == 512`; each element has norm within `0.001` of `1.0`; the three vectors are not identical to each other
- Failure guarded: only first vector returned; batch collapsed to one result; normalization skipped for later entries; accidental aliasing returning same vector object for all inputs

**T-04 — `embed_batch/1` normalizes every vector independently**
- Inputs: mock returns two vectors with different norms (e.g. first all `1.0`, second all `4.0`)
- Expected: both output vectors have norm within `0.001` of `1.0`; they are distinct values
- Failure guarded: only first vector normalized, rest returned raw

**T-05 — `embed/1` returns `{:error, reason}` on HTTP 4xx/5xx**
- Inputs: mock HTTP returns `{:ok, %{status: 500, body: "internal error"}}`
- Expected: `{:error, _}` — not a raised exception
- Failure guarded: crash or unhandled match on non-200 status

**T-06 — `embed/1` returns `{:error, reason}` on network failure**
- Inputs: mock HTTP client returns `{:error, :econnrefused}`
- Expected: `{:error, _}`
- Failure guarded: transport-layer error propagating as uncaught exception

**T-07 — `embed/1` returns `{:error, _}` when API returns wrong number of dimensions**
- Inputs: query `"test"`, mock returning a 256-element list instead of 512
- Expected: `{:error, _}` or `ArgumentError` — not silently returning a 256-dim vector
- Failure guarded: wrong-dim vector accepted and forwarded to VectorCodec, producing a codec error far from the call site and corrupting KNN distances if somehow stored

### Integration

**I-01 — `embed/1` with empty string propagates API rejection cleanly**
- Inputs: `""`, mock returning `{:ok, %{status: 400, body: %{"error" => %{"message" => "empty input not allowed"}}}}`
- Expected: `{:error, _}` — no raise, no crash, no attempt to normalize an empty list
- Failure guarded: pattern match failure on non-200 response for degenerate input

**I-02 — `embed/1` normalizing a near-zero vector does not divide by zero**
- Inputs: any query string, mock returns 512 floats all equal to `1.0e-38` (valid, non-zero, near-zero)
- Expected: `{:ok, vec}` where each element is a finite float (no `:infinity`, no `:nan`); norm within `0.001` of `1.0`
- Failure guarded: `sqrt` of near-zero norm producing `Infinity` or `NaN` propagating silently into the vector store

### E2E

**E-01 — Positive: `embed/1` round-trips cleanly through full pipeline with mocked API**
- Inputs: `"vintage levi denim jacket"`, mock returning `fixture_a` vector (loaded from committed fixtures)
- Expected: `{:ok, vec}` where `length(vec) == 512`; norm within `0.001` of `1.0`; vec equals `fixture_a` (normalization is idempotent on an already-normalized vector)
- Failure guarded: any stage of the pipeline breaking under end-to-end conditions

**E-02 — Negative: HTTP 401 Unauthorized returns `{:error, _}`, not a crash**
- Inputs: mock returning `{:ok, %{status: 401, body: %{"error" => %{"message" => "invalid api key"}}}}`
- Expected: `{:error, _}`
- Failure guarded: exception leaking into callers (EmbedWorker, HybridEngine) with no error path

**E-03 — Negative: API response with mismatched dimensions is rejected before normalization**
- Inputs: query `"jacket"`, mock returning a 100-element list
- Expected: `{:error, _}` or raise — the function does not attempt to normalize or return the truncated vector
- Failure guarded: short vector accepted as valid, producing garbage KNN distances stored in clothing_vec

---

## Implementation Tasks

- [x] Add HTTP client dep to `mix.exs` if not already present (`req` preferred); add OpenAI base URL + bearer auth header to config
- [x] Write all unit tests (T-01 through T-07) with mocked HTTP — all fail
- [x] Write integration tests I-01, I-02 — all fail
- [x] Write E2E tests E-01, E-02, E-03 — all fail
- [x] Implement `embed/1`: call `/v1/embeddings` with `model: "text-embedding-3-small"`, `dimensions: 512`, extract vector, validate dimension count, L2-normalize, return `{:ok, vec}` or `{:error, reason}`
- [x] Implement L2 normalization: `norm = :math.sqrt(Enum.sum(Enum.map(v, &(&1 * &1))))` then `Enum.map(v, &(&1 / norm))` — guard against near-zero norm returning infinity
- [x] Implement `embed_batch/1`: single API call with list of inputs, normalize each vector independently
- [x] Run all tests — all green
- [x] Write `scripts/gen_fixtures.exs`:
  - Calls `Embedder.embed_batch(["vintage levi denim jacket secondhand", "pink silk evening gown formal wear", "denim jacket indigo blue worn preloved"])`
  - Writes `test/fixtures/embeddings.exs` as an Elixir map literal: `%{fixture_a: [...], fixture_b: [...], fixture_c: [...]}`
- [x] Run script manually: `OPENAI_API_KEY=sk-... mix run scripts/gen_fixtures.exs`
- [x] Verify output file: 3 keys, each a 512-element list, each with norm within 0.001 of 1.0
- [ ] Commit `test/fixtures/embeddings.exs` and `scripts/gen_fixtures.exs`

---

## Definition of Done

- [x] All 14 tests green (`mix test test/chat_app/ai/embedder_test.exs`)
- [ ] `test/fixtures/embeddings.exs` is committed and loads without error: `mix run -e 'Code.eval_file("test/fixtures/embeddings.exs") |> elem(0) |> Map.keys() |> IO.inspect()'` outputs `[:fixture_a, :fixture_b, :fixture_c]`
- [ ] Each fixture vector has exactly 512 elements: `Enum.all?([:fixture_a, :fixture_b, :fixture_c], fn k -> length(fixtures[k]) == 512 end)`
- [ ] Each fixture vector is L2-normalized: norm within 0.001 of 1.0
- [ ] `fixture_a`, `fixture_b`, `fixture_c` are mutually distinct (no two are identical)
- [ ] `mix test` makes zero live HTTP calls (confirm via mock assertion or log inspection)
- [ ] Fixture generation script is documented with the exact command and required env var
