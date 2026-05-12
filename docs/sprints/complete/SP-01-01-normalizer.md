---
sprint_id: SP-01-01
phase: 1
status: complete
activated_date: 2026-05-06
completed_date: 2026-05-06
prerequisites: none
estimated_days: 1.5
---

# SP-01-01 — Test Infrastructure + Normalizer

**Goal:** Create Bypass fixture files and implement the stateless `Normalizer` module with full unit test coverage before any adapter touches a network.

---

## Scope

**In:**
- `test/support/http_mocks/` — 4 fixture files (eBay JSON, Depop JSON, Poshmark HTML, OpenAI embeddings JSON)
- Update `ChatApp.Clothing.Item` schema to expose `source`, `source_id`, `condition_normalized`, `last_scraped_at` (columns already exist in DB via `enhance_clothing_items` migration)
- `lib/chat_app/etl/normalizer.ex` — `normalize(source, raw_item) :: map`
- `test/chat_app/etl/normalizer_test.exs`
- `test/chat_app/clothing/item_test.exs` — schema contract tests

**Out:** HTTP adapters (eBay, Depop, Poshmark), Deduplicator, Workers, Scheduler. No `Repo`, HTTP, or process calls appear anywhere in this sprint's source or test files.

---

## Interface Contract

The normalizer receives `{source_string, raw_item_map}` where:

- **eBay** — raw map with string keys decoded from eBay Browse API JSON:
  `"itemId"`, `"title"`, `"price"` (nested: `%{"value" => "12.99"}`), `"condition"`, `"image"` (nested: `%{"imageUrl" => "..."}`), `"itemWebUrl"`

- **Depop** — raw map with string keys decoded from Depop API JSON:
  `"id"`, `"description"`, `"displayedPrice"`, `"brand"`, `"sizes"` (list), `"pictureUrl"`, `"slug"`

- **Poshmark** — map with string keys built by the Poshmark adapter from Floki extraction:
  `"source_id"`, `"title"`, `"price"`, `"brand"`, `"size"`, `"image_url"`, `"url"`, `"condition"`

The normalizer returns a map with atom keys ready for `ClothingItem.changeset/2`:
`source`, `source_id`, `title`, `price` (Decimal), `url`, `image_url`, `brand`, `size`, `condition_normalized`, `last_scraped_at`

---

## Test Suite

**File:** `test/chat_app/etl/normalizer_test.exs`
**Case:** `use ExUnit.Case, async: true` (pure functions; no DB, no HTTP)

### Unit Tests — field mapping

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `normalize/2 eBay maps all required fields` | `{"ebay", ebay_raw_item()}` — fixture map with all eBay keys present | Map contains `source: "ebay"`, `source_id: "v1\|123"`, `title: "..."`, `price: %Decimal{}`, `url: "https://..."`, `image_url: "https://..."` all non-nil | Field renamed during mapping; `source` field absent (deduplication silent failure) |
| 2 | `normalize/2 Depop maps all required fields` | `{"depop", depop_raw_item()}` — fixture map with all Depop keys | Map contains `source: "depop"`, `source_id: "abc123"`, `url: "https://depop.com/products/abc123"`, `brand: "Levi's"`, `size: "M"` | Slug not concatenated into URL; source field absent |
| 3 | `normalize/2 Poshmark maps all required fields` | `{"poshmark", poshmark_raw_item()}` — string-keyed map matching adapter output contract | Map contains `source: "poshmark"`, `source_id: "pm789"`, `title: "..."`, `price: %Decimal{}`, `url: "https://poshmark.com/..."`, `image_url: "https://..."` | Adapter/normalizer key contract mismatch; source field absent |

### Unit Tests — condition normalization

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 4 | `eBay "New" → condition_normalized: "new"` | `{"ebay", Map.put(ebay_raw_item(), "condition", "New")}` | `%{condition_normalized: "new"}` | Case sensitivity in condition map lookup |
| 5 | `eBay "Like New" → condition_normalized: "like_new"` | `{"ebay", Map.put(ebay_raw_item(), "condition", "Like New")}` | `%{condition_normalized: "like_new"}` | Hyphen vs underscore in output key |
| 6 | `eBay "Used" → condition_normalized: "good"` | `{"ebay", Map.put(ebay_raw_item(), "condition", "Used")}` | `%{condition_normalized: "good"}` | Missing entry in condition map |
| 7 | `Unrecognized condition defaults to "good"` | `{"ebay", Map.put(ebay_raw_item(), "condition", "Refurbished")}` | `%{condition_normalized: "good"}` | `Map.fetch!` crash instead of defaulted `Map.get` |
| 8 | `Depop condition always normalizes to "good"` | `{"depop", depop_raw_item()}` | `%{condition_normalized: "good"}` | Depop path not wired into condition logic; nil returned |
| 9 | `Poshmark "Like New" text → condition_normalized: "like_new"` | `{"poshmark", Map.put(poshmark_raw_item(), "condition", "Like New")}` | `%{condition_normalized: "like_new"}` | Poshmark not wired into condition normalization |
| 10 | `Poshmark nil condition → "good"` | `{"poshmark", Map.put(poshmark_raw_item(), "condition", nil)}` | `%{condition_normalized: "good"}` | nil crash in condition normalization |

### Unit Tests — nil and edge cases

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 11 | `nil image_url preserved as nil on eBay path` | `{"ebay", put_in(ebay_raw_item(), ["image", "imageUrl"], nil)}` | `%{image_url: nil}` | nil coerced to empty string; crash in nested access |
| 12 | `nil image_url preserved as nil on Depop path` | `{"depop", Map.put(depop_raw_item(), "pictureUrl", nil)}` | `%{image_url: nil}` | nil coerced to empty string |
| 13 | `Depop sizes: [] returns size: nil` | `{"depop", Map.put(depop_raw_item(), "sizes", [])}` | `%{size: nil}` | `Enum.at([], 0)` is nil but `List.first(nil)` crashes |
| 14 | `Depop sizes: nil returns size: nil` | `{"depop", Map.put(depop_raw_item(), "sizes", nil)}` | `%{size: nil}` | FunctionClauseError on nil passed to Enum.at |
| 15 | `brand field is present in output (may be nil) on eBay path` | `{"ebay", ebay_raw_item()}` | `Map.has_key?(result, :brand) == true` | Field missing entirely from normalized output |

### Unit Tests — price coercion

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 16 | `price as string coerces to Decimal` | `{"ebay", put_in(ebay_raw_item(), ["price", "value"], "12.99")}` | `%{price: Decimal.new("12.99")}` | Price stored as raw string; DB cast failure |
| 17 | `price as integer 0 coerces to Decimal` | `{"depop", Map.put(depop_raw_item(), "displayedPrice", 0)}` | `%{price: Decimal.new("0")}` | `Decimal.new(0)` returns integer Decimal; type mismatch |
| 18 | `price as float coerces to Decimal` | `{"depop", Map.put(depop_raw_item(), "displayedPrice", 9.99)}` | `is_struct(result.price, Decimal) == true` | Float imprecision stored in DB (9.989999...) |
| 19 | `price nil returns nil` | `{"ebay", put_in(ebay_raw_item(), ["price", "value"], nil)}` | `%{price: nil}` | `Decimal.new(nil)` raises ArgumentError |

### Unit Tests — timestamp and unknown source

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 20 | `last_scraped_at is a UTC DateTime struct` | `{"ebay", ebay_raw_item()}` | `is_struct(result.last_scraped_at, DateTime) == true` AND `result.last_scraped_at.time_zone == "Etc/UTC"` | Naive datetime returned; field absent; UTC offset applied |
| 21 | `normalize/2 unknown source raises FunctionClauseError` | `{"etsy", %{}}` | raises `FunctionClauseError` | Silent nil return propagating bad data to deduplicator |

### Fixture Validation Tests

**File:** `test/chat_app/etl/fixtures_test.exs`

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 22 | `ebay_search_response.json is valid JSON with ≥ 20 itemSummaries` | Read + `Jason.decode!/1` | `length(body["itemSummaries"]) >= 20` | Malformed JSON surfaces as cryptic match error inside test helper |
| 23 | `depop_search_response.json is valid JSON with ≥ 24 items` | Read + `Jason.decode!/1` | `length(body["products"]) >= 24` | Wrong top-level key; truncated fixture |
| 24 | `poshmark_search.html contains ≥ 20 elements with data-id attribute` | Read + `Floki.parse_document!/1` | `length(Floki.find(doc, "[data-id]")) >= 20` | Fixture has too few listings; Floki selector returns empty list |
| 25 | `openai_embeddings_response.json has 20 embeddings each of length 512` | Read + `Jason.decode!/1` | `length(body["data"]) == 20` AND every `item["embedding"]` has `length == 512` | Wrong dimension count used in VectorCodec; fixture truncated |

### Schema Tests

**File:** `test/chat_app/clothing/item_test.exs`
**Case:** `use ExUnit.Case, async: true` (changeset tests only; no DB)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 26 | `Item changeset accepts ETL fields` | `%Item{} \|> Item.changeset(valid_attrs_with_etl_fields())` where attrs include `source: "ebay"`, `source_id: "v1\|123"`, `condition_normalized: "good"`, `last_scraped_at: DateTime.utc_now()` | `changeset.valid? == true` | New DB columns not reflected in schema or cast list |
| 27 | `Item changeset errors when source absent` | `%Item{} \|> Item.changeset(Map.delete(valid_attrs(), :source))` | `changeset.valid? == false` AND `:source in Keyword.keys(changeset.errors)` | source silently nil (null: false migration constraint not enforced in changeset) |

---

## Fixture File Specifications

**`test/support/http_mocks/ebay_search_response.json`**
Top-level keys: `"total"`, `"itemSummaries"` (array of ≥ 20 objects). Each object must have:
`"itemId"` (e.g. `"v1|123456789|0"`), `"title"`, `"price"` (`{"value": "12.99", "currency": "USD"}`), `"condition"` (one of `"New"`, `"Like New"`, `"Used"`), `"image"` (`{"imageUrl": "https://..."}`), `"itemWebUrl"`. Use realistic-looking synthetic data.

**`test/support/http_mocks/depop_search_response.json`**
Top-level key: `"products"` (array of ≥ 24 objects). Each object must have:
`"id"`, `"description"`, `"displayedPrice"` (numeric), `"brand"`, `"sizes"` (array of strings), `"pictureUrl"`, `"slug"`. At least one item must have `"sizes": []` and one must have a null `"pictureUrl"` to exercise edge-case paths.

**`test/support/http_mocks/poshmark_search.html`**
Valid HTML. ≥ 20 listing elements, each containing: `data-id` attribute, `.listing__title`, `.listing__ipad-price`, `.listing__brand`, `.listing__size`, `img[src]`, `a[href]` (relative path). At least one listing must omit `.listing__size` to exercise the nil-size path.

**`test/support/http_mocks/openai_embeddings_response.json`**
Top-level keys: `"object": "list"`, `"data"` (array of exactly 20 objects). Each object: `"object": "embedding"`, `"index"` (0–19), `"embedding"` (array of exactly 512 floats between -1.0 and 1.0). `"model": "text-embedding-3-small"`.

---

## Implementation Tasks (TDD Order)

1. ✅ **Create all 4 fixture files** — tests 22–25 cannot compile their helpers without them.
2. ✅ **Write all 27 tests** — all red. No implementation files created yet.
3. ✅ **Update `ChatApp.Clothing.Item`** — add `source`, `source_id`, `condition_normalized`, `last_scraped_at` to `schema` fields and `changeset/2` cast and validate lists. Add `validate_required(:source)`. Tests 26–27 go green.
4. ✅ **Create `lib/chat_app/etl/normalizer.ex`** — module skeleton with `normalize/2` stubs returning `{:error, :not_implemented}`.
5. ✅ **Implement `normalize("ebay", raw)`** — field mapping per spec table; `Decimal.new/1` for price with nil guard; `DateTime.utc_now()` for `last_scraped_at`. Tests 1, 11, 16–20 begin going green.
6. ✅ **Implement `normalize("depop", raw)`** — slug URL concatenation; `Enum.at(sizes || [], 0)` for size. Tests 2, 12–14 go green.
7. ✅ **Implement `normalize("poshmark", raw)`** — direct field pass-through from string-keyed adapter map. Test 3 goes green.
8. ✅ **Implement `normalize_condition/1`** — private function using `Map.get(condition_map, raw_condition, "good")`. Tests 4–10 go green.
9. ✅ **Run full suite** — all 27 green.

---

## Definition of Done

- `mix test test/chat_app/etl/normalizer_test.exs test/chat_app/etl/fixtures_test.exs test/chat_app/clothing/item_test.exs` — 27/27 green, zero skips
- `grep -rn "Repo\." test/chat_app/etl/normalizer_test.exs` returns no hits
- `grep -rn "Req\.\|HTTPoison\.\|Process\." lib/chat_app/etl/normalizer.ex` returns no hits
- `mix compile --warnings-as-errors` clean
- All 4 fixture files exist and pass their own validation tests
- `ClothingItem.changeset/2` rejects attrs without `source`
