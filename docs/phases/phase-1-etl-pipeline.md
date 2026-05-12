---
status: complete
last_updated: 2026-05-11
phase: 1
sub_phase: 1
slug: etl-pipeline
complexity: M
---

# Phase 1 — ETL Pipeline

**Goal:** Pull real clothing listings from eBay, Depop, and Poshmark on a 2-hour schedule and persist normalized, deduplicated, embedded records.

---

## Deliverables

### Source Adapters

**`lib/chat_app/etl/sources/ebay.ex`** ✅ (SP-01-02)
- OAuth Client Credentials Grant; token cached in ETS, refreshed when `expires_at < DateTime.utc_now()`
- Token endpoint: `EBAY_API_BASE_URL <> "/identity/v1/oauth2/token"` (env var; default `https://api.sandbox.ebay.com` in dev, `https://api.ebay.com` in prod)
- Search endpoint: `EBAY_API_BASE_URL <> "/buy/browse/v1/item_summary/search?q={q}&category_ids=15724,11450&limit=50"`
- Map response fields: `itemId`, `title`, `price.value`, `condition`, `image.imageUrl`, `itemWebUrl`

**`lib/chat_app/etl/sources/depop.ex`** ✅ (SP-01-03)
- Endpoint: `https://api.depop.com/api/v3/search?q={q}&limit=24`
- Headers: `User-Agent: Mozilla/5.0`, `Accept-Language: en-US`
- Map response fields: `id`, `description`, `displayedPrice`, `brand`, `sizes[0]`, `pictureUrl`, `slug` → URL: `"https://depop.com/products/" <> slug`

**`lib/chat_app/etl/sources/poshmark.ex`** ✅ (SP-01-04)
- Endpoint: `https://poshmark.com/search?query={q}&type=listings&src=dir`
- Parse with Floki: `.listing__title`, `.listing__ipad-price`, `.listing__brand`, `.listing__size`, `img[src]`, `a[href]`, `data-id` attribute

### Normalization (`lib/chat_app/etl/normalizer.ex`) ✅ (SP-01-01)

Field mapping per source:

| Output field | eBay | Depop | Poshmark (Floki) |
|---|---|---|---|
| `source_id` | `itemId` | `id` | `data-id` attr |
| `title` | `title` | `description` | `.listing__title` |
| `price` | `price.value` | `displayedPrice` | `.listing__ipad-price` |
| `url` | `itemWebUrl` | `"https://depop.com/products/" <> slug` | `a[href]` |
| `image_url` | `image.imageUrl` | `pictureUrl` | `img[src]` |
| `brand` | parse from title | `brand` | `.listing__brand` |
| `size` | parse from title | `sizes[0]` | `.listing__size` |
| `condition_normalized` | map "Used"→`good`, "Like New"→`like_new`, "New"→`new` | `"good"`→`good` | `.listing__condition` text |

Condition normalization map covers: `new`, `like_new`, `good`, `fair`, `poor`. Unrecognized values default to `good`. Nil `image_url` → `nil` (handled by UI fallback).

### Deduplication (`lib/chat_app/etl/deduplicator.ex`) ✅ (SP-01-05)

```elixir
Repo.insert(changeset,
  on_conflict: {:replace, [:price, :last_scraped_at, :image_url, :size, :condition_normalized]},
  conflict_target: [:source, :source_id]
)
```

Always write one `price_history` row per upsert call regardless of whether price changed. Atomic transaction ensures item and price_history commit together.

### Workers

**`lib/chat_app/etl/workers/scrape_worker.ex`** ✅ (SP-01-06)
- `use Oban.Worker, queue: :scraper, max_attempts: 3`
- `perform(%Job{args: %{"source" => source, "query" => query}})`
- After normalizing + upserting all items, enqueue one `EmbedWorker` job per 20-item chunk (args: `%{"item_ids" => [id, ...]}`)

**`lib/chat_app/etl/workers/embed_worker.ex`** ✅ (SP-01-07)
- `use Oban.Worker, queue: :embedder, max_attempts: 3`
- Receives `%{"item_ids" => [id, ...]}` (up to 20)
- Calls `Embedder.embed_batch(texts)` — one OpenAI request for all 20 items
- Stores encoded binary in `clothing_items.embedding` (via VectorCodec)
- Upserts each vector into `clothing_vec` (DELETE + INSERT; vec0 does not support ON CONFLICT)
- Calls `FTS5Index.upsert(item_id)` for each item

**`lib/chat_app/etl/embedder.ex`** ✅ (SP-01-07)
- `embed_batch(texts :: [String.t()]) :: {:ok, [[float()]]} | {:error, term()}`
- POST to OpenAI `text-embedding-3-small` with `dimensions: 512`
- Parses response, sorts by index, extracts embedding vectors

**`lib/chat_app/etl/fts5_index.ex`** ✅ (SP-01-07)
- `upsert(item_id :: integer()) :: :ok`
- Inserts item's title into FTS5 shadow index (non-bang; duplicate-rowid inserts fail silently on retry)

### Scheduler (`config/config.exs`) ✅ (SP-01-08)

```elixir
config :chat_app, Oban,
  plugins: [
    {Oban.Plugins.Cron,
      crontab: [
        {"0 */2 * * *", ChatApp.ETL.Workers.ScrapeWorker,
         args: %{"queries" => @scrape_queries}}
      ]}
  ]
```

Default seed queries (in `config/config.exs`):
```elixir
config :chat_app, :scrape_queries, [
  "vintage levi",
  "y2k denim",
  "silk slip dress",
  "90s windbreaker",
  "cashmere sweater"
]
```

### Test Support

**`test/support/http_mocks/`** — Bypass fixture files:
- `ebay_search_response.json` — realistic eBay Browse API JSON with 20+ items
- `depop_search_response.json` — realistic Depop internal API JSON
- `poshmark_search.html` — realistic Poshmark search results HTML
- `openai_embeddings_response.json` — realistic embeddings API response for 20 items

---

## Acceptance Criteria

- **Scrape + normalize (mocked):** `ScrapeWorker.perform/1` with Bypass mocking the eBay endpoint → `ClothingItem |> where(source: "ebay") |> Repo.aggregate(:count)` ≥ 20 AND all rows have non-null `title`, `price`, `source_id`, `url`
- **Idempotency:** Run the same worker twice with the same Bypass mock → row count before second run equals row count after; no unique constraint errors raised
- **Price history:** After one scrape run of N items, `PriceHistory |> Repo.aggregate(:count)` = N; after a second run, = 2N (one row per item per run, always written)
- **EmbedWorker batching:** With 25 items scraped, assert exactly 2 `EmbedWorker` jobs enqueued (chunk of 20 + chunk of 5); verify via `Oban.Job |> where(worker: "EmbedWorker") |> Repo.aggregate(:count)` = 2
- **OAuth token refresh (unit):** Seed ETS token cache with `%{token: "old_token", expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}`; call `Ebay.get_token/0` with Bypass mock for OAuth endpoint returning `%{"access_token" => "new_token"}`; assert returned value = `"new_token"` and cache `expires_at` > `DateTime.utc_now()`
- **Scheduler registration:** ✅ (SP-01-08) Cron plugin wired to enqueue ScrapeWorker with 2-hour cadence (`"0 */2 * * *"`) and `"queries"` dispatch clause routes to per-source-per-query jobs

---

## Dependencies

- Phase 0 complete (schema, migrations, VectorCodec)
- `EBAY_APP_ID`, `EBAY_CERT_ID`, `EBAY_API_BASE_URL` in `.env`
- `OPENAI_API_KEY` already present

---

## Complexity: M

Three distinct source formats, OAuth token caching, Oban job chaining, and Bypass mock setup all in one phase. Unofficial Depop/Poshmark sources require field mapping iteration against live HTML/JSON.

---

## Risks

- **Depop rate limits:** Add `User-Agent: Mozilla/5.0` and `Accept-Language: en-US` headers. If still rate-limited, add a 1-second sleep between pages.
- **Poshmark HTML drift:** CSS selectors are hardcoded. If Poshmark changes their HTML structure, Floki selectors must be updated. Add a test that parses the fixture HTML and asserts field presence.
- **First-scrape OpenAI burst:** 5 queries × 50 items = 250 items → 13 EmbedWorker jobs → 13 OpenAI calls in rapid succession. `text-embedding-3-small` tier-1 limit is 3000 RPM. At 13 calls this is fine; at larger scales, add `Process.sleep(200)` between batch calls in EmbedWorker.
- **eBay sandbox vs production:** Sandbox returns synthetic data. Use `EBAY_API_BASE_URL=https://api.sandbox.ebay.com` in dev to verify API connectivity without consuming production quota.
