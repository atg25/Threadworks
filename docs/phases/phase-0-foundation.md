---
status: complete
last_updated: 2026-05-06
completed_date: 2026-05-06
phase: 4
sub_phase: 0
slug: foundation
complexity: S
---

# Phase 0 — Foundation

**Goal:** Establish the dependency and schema baseline everything else builds on.

---

## Deliverables

- **`mix.exs`** — add `{:oban, "~> 2.17"}` and sqlite_vec (verify Hex name via `mix hex.search sqlite_vec` before adding; if only available as a Git dep, use `{:sqlite_vec, github: "joelpaulkoch/sqlite_vec", ref: "<commit>"}`)
- **`config/config.exs`** — `config :chat_app, Oban, repo: ChatApp.Repo, queues: [scraper: 3, embedder: 5]`
- **`lib/chat_app/application.ex`** — add `{Oban, Application.fetch_env!(:chat_app, Oban)}` to supervision tree children
- **`lib/chat_app/ai/vector_codec.ex`** — `encode(floats)` → binary (512 × float32 big-endian), `decode(binary)` → float list
- **`.env.example`** — add `EBAY_APP_ID`, `EBAY_CERT_ID`, `EBAY_API_BASE_URL` with descriptions

### Migrations (run in this order)

| Order | File | Notes |
|---|---|---|
| 1 | `_add_oban_jobs_table` | `Oban.Migration.up(version: 12)` |
| 2 | `_enhance_clothing_items` | Add columns + unique index |
| 3 | `_create_price_history` | FK → clothing_items |
| 4 | `_create_saved_items` | FK → users + clothing_items; UNIQUE(user_id, item_id) |
| 5 | `_create_user_preferences` | FK → users (unique per user) |
| 6 | `_create_clothing_fts` | FTS5 virtual table; must follow migration 2 |
| 7 | `_create_clothing_vec` | sqlite-vec virtual table |

### `_enhance_clothing_items` column additions

| Column | Type | Notes |
|---|---|---|
| `source` | `:string` | `"ebay"`, `"depop"`, `"poshmark"` |
| `source_id` | `:string` | Platform-native item ID |
| `color` | `:string` | Nullable |
| `style_tags` | `:string` | JSON array, e.g. `["vintage","y2k"]` |
| `size_normalized` | `:string` | Nullable |
| `condition_normalized` | `:string` | One of: `new`, `like_new`, `good`, `fair`, `poor` |
| `last_scraped_at` | `:utc_datetime` | Updated each scrape run |
| `embedding` | `:binary` | 2048 bytes (512 × float32 big-endian via VectorCodec) |

Add unique index: `create unique_index(:clothing_items, [:source, :source_id])`

### `_create_saved_items` schema

```
user_id       :integer FK users (not null)
item_id       :integer FK clothing_items ON DELETE SET NULL
price_at_save :decimal
notes         :string
inserted_at   :utc_datetime
```

Unique index: `unique_index(:saved_items, [:user_id, :item_id])`

`ON DELETE SET NULL` on `item_id`: when a scraped item is removed from `clothing_items`, the saved_items row remains with `item_id = nil` so the UI can show "Listing Removed" rather than silently deleting it.

### `_create_clothing_fts` SQL

```sql
CREATE VIRTUAL TABLE clothing_fts USING fts5(
  title, brand, description, size, color, style_tags,
  content='clothing_items', content_rowid='id'
);
```

### `_create_clothing_vec` SQL

```sql
CREATE VIRTUAL TABLE clothing_vec USING vec0(embedding float[512]);
```

---

## Acceptance Criteria

- `mix deps.get && mix compile` exits 0 with no missing-package warnings
- `mix ecto.migrate` runs all 7 migrations in order; running a second time is a no-op
- `mix test` (existing suite) passes without modifications
- `Oban.config().queues` in iex contains `scraper: 3` and `embedder: 5`
- FTS5 functional: insert one `clothing_items` row with title `"Levi Jacket"`, run `INSERT INTO clothing_fts(clothing_fts) VALUES('rebuild')`, then `SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'levi'` returns a non-empty result
- `VectorCodec.encode(List.duplicate(0.0, 511) ++ [1.0])` returns a binary of exactly 2048 bytes; `VectorCodec.decode(that_binary)` round-trips to the original list within float32 precision (each value within 0.0001)

---

## Dependencies

None — this is the baseline.

---

## Complexity: S

Config and SQL migrations only. No application logic. Primary risk is sqlite_vec package availability on Hex.

---

## Risks

- **sqlite_vec Hex availability:** Run `mix hex.search sqlite_vec` before starting. If not on Hex, use a Git dep and pin to a specific commit hash so the build is reproducible.
- **Oban migration version:** `Oban.Migration.up(version: 12)` must match the installed Oban version. Check the Oban changelog if the version number differs.
- **FTS5 content table ordering:** Migration 6 references `clothing_items` as a content table. It must run after migration 2 or the `CREATE VIRTUAL TABLE` statement will fail.
