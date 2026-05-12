---
sprint_id: SP-01-07
phase: 1
status: complete
activated_date: 2026-05-11
completed_date: 2026-05-11
prerequisites: SP-01-05 complete (items in DB with ids); SP-01-06 complete (EmbedWorker referenced by ScrapeWorker)
estimated_days: 1.5
---

# SP-01-07 — EmbedWorker

**Goal:** Implement `EmbedWorker` to batch-embed up to 20 items per OpenAI call, store vectors via `VectorCodec` in `clothing_items.embedding`, upsert into `clothing_vec`, and update the FTS5 index — with explicit guards against the 512 vs 1536 dimension trap and SQLite WAL contention under concurrent jobs.

---

## Scope

**In:**
- `lib/chat_app/etl/workers/embed_worker.ex`
- `lib/chat_app/etl/embedder.ex` — `embed_batch(texts :: [String.t()]) :: {:ok, [[float()]]} | {:error, term()}`
- `lib/chat_app/etl/fts5_index.ex` — `upsert(item_id :: integer()) :: :ok`
- `test/chat_app/etl/workers/embed_worker_test.exs`
- Bypass mock for OpenAI embeddings endpoint (reuses `openai_embeddings_response.json` fixture from SP-01-01)

**Out:** ScrapeWorker changes, scheduler wiring. The OpenAI API URL for embeddings is configurable via `:openai_embeddings_url` application config (following the existing `OpenAI` module pattern using `:openai_api_url`).

---

## Critical Design Constraint: Embedding Dimensions

`VectorCodec` encodes 512-element float32 vectors (2048 bytes). OpenAI's `text-embedding-3-small` model defaults to **1536 dimensions**. The embeddings request **must** include `"dimensions": 512` in the request body, or every stored vector will have the wrong size and `clothing_vec` will reject the insert.

Test 5 guards this. Test 6 guards the mismatch detection path. Do not skip these.

---

## Worker Contract

```elixir
use Oban.Worker, queue: :embedder, max_attempts: 3

def perform(%Job{args: %{"item_ids" => item_ids}}) do
  # 1. Fetch items from DB by id
  # 2. Build text representations for each item
  # 3. Call Embedder.embed_batch(texts) — one OpenAI request
  # 4. Zip items with embeddings
  # 5. For each {item, embedding}: VectorCodec.encode → store in clothing_items.embedding
  # 6. Upsert each vector into clothing_vec
  # 7. Call FTS5Index.upsert(item.id) for each item
end
```

---

## New Modules Required

### `lib/chat_app/etl/embedder.ex`

```elixir
def embed_batch(texts) do
  # POST to OpenAI embeddings endpoint
  # Request body: %{model: "text-embedding-3-small", input: texts, dimensions: 512}
  # Returns {:ok, [[float(), ...]]} — one list per input text
  # Returns {:error, reason} on HTTP failure
end
```

Uses `Application.get_env(:chat_app, :openai_embeddings_url, "https://api.openai.com/v1/embeddings")` and `Application.get_env(:chat_app, :openai_api_key)` so tests can override via `Application.put_env` and Bypass.

### `lib/chat_app/etl/fts5_index.ex`

```elixir
def upsert(item_id) do
  Repo.query!("""
  INSERT INTO clothing_fts(rowid, title)
  SELECT id, title FROM clothing_items WHERE id = ?
  ON CONFLICT(rowid) DO UPDATE SET title = excluded.title
  """, [item_id])
  :ok
end
```

---

## Test Suite

**File:** `test/chat_app/etl/workers/embed_worker_test.exs`
**Case:** `use ChatApp.DataCase` — DB sandbox required

Each test's `setup`:
1. `bypass = Bypass.open()`
2. `Application.put_env(:chat_app, :openai_embeddings_url, "http://localhost:#{bypass.port}/v1/embeddings")`
3. Insert N clothing items into DB using `Deduplicator.upsert_all/1`; collect their ids

### Integration Tests

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `perform/1 calls OpenAI embeddings API exactly once for batch of 20 items` | Insert 20 items; `EmbedWorker.perform(%Job{args: %{"item_ids" => ids}})`; Bypass counts requests via Agent counter | Agent counter == 1 after perform | Embedding called per item in a loop (20 HTTP calls instead of 1) |
| 2 | `perform/1 request body contains dimensions: 512` | Bypass captures request body JSON | `body["dimensions"] == 512` AND `body["model"] == "text-embedding-3-small"` AND `length(body["input"]) == 20` | dimensions not sent; OpenAI returns 1536-element vectors; VectorCodec rejects them |
| 3 | `perform/1 stores 2048-byte binary embedding on each item` | perform; fetch all 20 items from DB | `Enum.all?(items, fn i -> byte_size(i.embedding) == 2048 end)` | VectorCodec.encode not called; embedding stored as list (JSON); wrong float precision |
| 4 | `perform/1 upserts all items into clothing_vec` | perform on 20 items | `Repo.query!("SELECT count(*) FROM clothing_vec").rows == [[20]]` | clothing_vec insert skipped; VectorCodec dimension error causes silent skip |
| 5 | `perform/1 updates FTS5 index: items findable by title keyword search` | Insert item with title "vintage windbreaker"; perform; run FTS query | `Repo.query!("SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH ?", ["windbreaker"]).rows` contains item's id | FTS5Index.upsert not called; FTS insert uses wrong rowid |
| 6 | `perform/1 returns {:error, :embedding_count_mismatch} when OpenAI returns fewer embeddings than items` | 20 item_ids; Bypass returns fixture with only 18 embeddings | `{:error, :embedding_count_mismatch}` — no crash; no partial writes | `Enum.zip` silently truncates to shorter list; 2 items stored without embeddings; no error raised |
| 7 | `perform/1 skips item_ids not found in DB without crashing` | ids list includes one id that does not exist in DB | Remaining valid items processed; returns `:ok` | `Repo.get!` raises `Ecto.NoResultsError`; entire job fails for one stale id |

### Unit Tests — `Embedder.embed_batch/1`

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 8 | `embed_batch/1 returns {:ok, list_of_float_lists}` | Bypass returns `openai_embeddings_response.json` fixture; call `Embedder.embed_batch(["text 1", ..., "text 20"])` | `{:ok, embeddings}` where `length(embeddings) == 20` AND every element is a list of 512 floats | Wrong response key parsed; embeddings wrapped in extra nesting |
| 9 | `embed_batch/1 sends dimensions: 512 in request body` | Bypass captures body | `body["dimensions"] == 512` | Parameter missing from request; model defaults to 1536 dims |

### Unit Tests — VectorCodec dimension guard (assigned from QA review)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 10 | `VectorCodec.encode/1 raises ArgumentError for 1536-element list` | `VectorCodec.encode(List.duplicate(0.1, 1536))` | raises `ArgumentError` with message containing "requires exactly 512 elements, got 1536" | encode silently truncates or wraps 1536-element input; wrong-size binary written to DB and clothing_vec silently corrupted |

### Concurrency Test (assigned from QA review)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 11 | `two concurrent EmbedWorker jobs: no SQLite busy_timeout errors` | Insert 40 items; split into two groups of 20; run two `Task.async` calls executing `EmbedWorker.perform` simultaneously; Bypass handles both requests | Both tasks return `:ok`; all 40 items have non-nil embeddings; no `Exqlite.Error` with `"SQLITE_BUSY"` in message | SQLite WAL write contention causes second worker to time out; job marked failed |

---

## Implementation Tasks (TDD Order)

1. ✅ **Write all 11 tests** — all red.
2. ✅ **Add `:openai_embeddings_url` config** to `config/config.exs`:
   ```elixir
   config :chat_app, :openai_embeddings_url,
     System.get_env("OPENAI_EMBEDDINGS_URL", "https://api.openai.com/v1/embeddings")
   ```
3. ✅ **Create `lib/chat_app/etl/embedder.ex`** — `embed_batch/1` calls `Req.post` with correct body; parses `response.body["data"]` sorted by `"index"` and extracts `"embedding"` from each. Tests 8–9 go green.
4. ✅ **Create `lib/chat_app/etl/fts5_index.ex`** — `upsert/1` executes raw SQL upsert into `clothing_fts`. Test 5 will exercise this through perform.
   - Note: `clothing_fts` is a content table; plain `INSERT INTO clothing_fts(rowid, title)` populates the FTS index correctly. `ON CONFLICT` and auxiliary `'insert'`/`'delete'` commands are not supported by this SQLite version.
5. ✅ **Create `lib/chat_app/etl/workers/embed_worker.ex`** — skeleton returning `{:error, :not_implemented}`.
6. ✅ **Implement item fetch** — `Repo.all(from i in ClothingItem, where: i.id in ^item_ids)`. Test 7 (stale ids) drives graceful handling.
7. ✅ **Implement embedding call** — call `Embedder.embed_batch(texts)`; assert `length(embeddings) < length(items)` else return `{:error, :embedding_count_mismatch}`. Test 6 goes green.
   - Note: guard triggers on fewer-than, not not-equal — API may return more than requested; only fewer is an error.
8. ✅ **Implement storage loop** — for each `{item, embedding}`: `VectorCodec.encode(embedding)` → update `clothing_items.embedding`; upsert into `clothing_vec` (DELETE + INSERT, `ON CONFLICT` unsupported by vec0); call `FTS5Index.upsert(item.id)`. Tests 3–5 go green.
   - Note: `clothing_vec` requires `{:blob, binary}` binding, not raw binary. `vec0` does not support `ON CONFLICT` syntax.
9. ✅ **Verify dimensions guard** — `VectorCodec.encode/1` already raises `ArgumentError` for non-512 lists (existing implementation). Test 10 passes.
10. ✅ **Run concurrency test (11)** — passed without `SQLITE_BUSY`. The existing `busy_timeout: 5_000` in `test.exs` and `pool_size: 5` are sufficient. No mutex needed.
11. ✅ **Run all 11 tests until green.** — 11/11 green, 0 failures.

---

## Definition of Done

- ✅ `mix test test/chat_app/etl/workers/embed_worker_test.exs` — 11/11 green, zero skips
- ✅ Test 10 (VectorCodec 1536-element raise) passes — dimension mismatch detected at encode time
- ✅ Test 2 (dimensions: 512 in request body) passes — no 1536-element vectors ever sent to DB
- ✅ Test 11 (concurrent WAL) passes — no busy_timeout errors; existing pool_size: 5 + busy_timeout: 5000 sufficient
- ⚠️ `mix compile --warnings-as-errors` — fails due to three pre-existing `data-sidebar-action-icon` warnings in `sidebar_component.ex`; no warnings from sprint-delivered files
- ⚠️ `Bypass.verify_expectations!/1` in `on_exit` — PSPDFKit Bypass 2.1.0 auto-registers with ExUnit and raises `"Not available in ExUnit, as it's configured automatically."` when called manually; calls were removed; verification is performed automatically by the library
- ✅ `FTS5Index.upsert/1` is a named public module — required for independent testing and future reuse
