---
sprint_id: SP-01-04
phase: 1
status: complete
activated_date: 2026-05-10
completed_date: 2026-05-11
prerequisites: SP-01-01 complete
estimated_days: 1.5
---

# SP-01-04 — Poshmark Source Adapter

**Goal:** Implement the Poshmark scraper with a pure, fully-unit-tested `parse_html/1` function and a Bypass-verified `fetch_items/1`, so HTML selector regressions are caught at the unit level before they reach the network.

---

## Scope

**In:**
- `lib/chat_app/etl/sources/poshmark.ex` — public API: `fetch_items/1`; private: `parse_html/1`
- `parse_html/1` is extracted as a `@doc false` public function to enable direct unit testing
- Add `:poshmark_base_url` config key to `config/config.exs` and `config/test.exs`
- `test/chat_app/etl/sources/poshmark_test.exs`

**Out:** Normalizer calls — adapter produces string-keyed maps from Floki extraction; `Normalizer.normalize("poshmark", raw)` handles field mapping. No auth, no ETS, no ScrapeWorker wiring. CSS selectors are hardcoded per spec; selector maintenance is explicitly a known risk.

---

## Configuration

Add to `config/config.exs`:
```elixir
config :chat_app, :poshmark_base_url,
  System.get_env("POSHMARK_BASE_URL", "https://poshmark.com")
```

---

## Interface Contract

`parse_html/1` accepts an HTML binary string and returns `{:ok, [raw_map]}` or `{:ok, []}`.

Each raw map is string-keyed, built from Floki extraction:
```
"source_id"  ← data-id attribute on the listing root element
"title"      ← text content of .listing__title
"price"      ← text content of .listing__ipad-price (raw string, may have $ prefix)
"brand"      ← text content of .listing__brand
"size"       ← text content of .listing__size (nil if element absent)
"image_url"  ← src attribute of img (nil if absent)
"url"        ← absolute URL built from href attribute of a (prepend :poshmark_base_url if href is relative)
"condition"  ← text content of .listing__condition (nil if element absent)
```

The Normalizer handles all value transformation (price Decimal coercion, condition normalization).

---

## Test Suite

**File:** `test/chat_app/etl/sources/poshmark_test.exs`
**Case:** `use ExUnit.Case, async: false`

Fixture loaded once in `setup_all`:
```elixir
@fixture File.read!("test/support/http_mocks/poshmark_search.html")
```

### Unit Tests — `parse_html/1` (pure; no HTTP, no DB)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `parse_html/1 returns one map per listing with data-id` | `@fixture` | `{:ok, items}` where `length(items) == Floki.find(doc, "[data-id]") \|> length()` | Selector returns wrong container; count mismatch |
| 2 | `parse_html/1 extracts source_id from data-id attribute` | `@fixture`; inspect first item | `result["source_id"]` is a non-empty string matching the fixture's `data-id` value | Attribute name typo (`data_id`, `id`); Floki attribute access path wrong |
| 3 | `parse_html/1 extracts title from .listing__title` | `@fixture`; inspect first item | `result["title"]` is a non-empty string; `String.trim(result["title"]) != ""` | Selector wrong; text/0 returns nested HTML not plain text |
| 4 | `parse_html/1 extracts price from .listing__ipad-price` | `@fixture`; inspect first item | `result["price"]` is a non-empty string | Wrong selector (`.listing__price` vs `.listing__ipad-price`) |
| 5 | `parse_html/1 extracts brand from .listing__brand` | `@fixture`; inspect first item | `result["brand"]` is a non-empty string | Selector missing; brand nil for all items |
| 6 | `parse_html/1 extracts size from .listing__size` | `@fixture`; inspect first item that has a size element | `result["size"]` is a non-empty string | Selector missing; size nil for all items including those that have it |
| 7 | `parse_html/1 extracts image_url from img[src]` | `@fixture`; inspect first item | `result["image_url"]` starts with `"https://"` | Lazy-load placeholder `src` used (`data-src`); relative URL returned |
| 8 | `parse_html/1 builds absolute URL from a[href]` | `@fixture`; inspect first item where href is relative (e.g. `/listing/abc`) | `result["url"]` == `"https://poshmark.com" <> "/listing/abc"` | Relative href stored as-is; dead URL in production |
| 9 | `parse_html/1 returns size: nil when .listing__size absent` | Fixture item modified to remove `.listing__size` element (use inline HTML string) | That item's `result["size"] == nil` | `Floki.find` returns `[]`; `List.first([])` returns nil — guards crash via head on empty list |
| 10 | `parse_html/1 returns image_url: nil when img[src] absent` | Inline HTML string with listing that has no img tag | `result["image_url"] == nil` | nil crash in src attribute access |
| 11 | `parse_html/1 returns {:ok, []} on HTML with no listing elements` | `"<html><body><p>No results</p></body></html>"` | `{:ok, []}` | Crash on empty Floki result; FunctionClauseError on empty pattern match |

### Selector Regression Test

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 12 | `All 5 CSS selectors return at least one match in fixture HTML` | `@fixture`; run each selector individually | `Floki.find(doc, "[data-id]")` non-empty; `.listing__title` non-empty; `.listing__ipad-price` non-empty; `.listing__brand` non-empty; `.listing__size` non-empty | Most common HTML drift failure: selector silently returns `[]` causing all items to have nil fields — no individual test catches this if the fixture itself has no elements matching the selector |

### Integration Tests — `fetch_items/1` (Bypass-mocked)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 13 | `fetch_items/1 sends GET to Poshmark search URL with query params` | Bypass captures `conn`; expect GET on `/search` | `conn.query_string` contains `query=vintage+levi`, `type=listings`, `src=dir` | Wrong path; missing query params; wrong param names |
| 14 | `fetch_items/1 parses Bypass-served HTML and returns items` | Bypass serves `@fixture` with `Content-Type: text/html`; call `fetch_items("vintage levi")` | `{:ok, items}` where `length(items) > 0` | HTTP call succeeds but HTML not passed to `parse_html/1`; response body not read |
| 15 | `fetch_items/1 returns {:error, :timeout} on network timeout` | Bypass closes connection before responding | `{:error, :timeout}` | `Req.TransportError` propagates uncaught |
| 16 | `fetch_items/1 returns {:ok, []} on non-200 response` | Bypass returns 503 | `{:ok, []}` | Non-2xx response crashes or raises; scrape worker stops for one source failure |

---

## Implementation Tasks (TDD Order)

1. [x] **Write all 16 tests** — all red.
2. [x] **Add `:poshmark_base_url` config** to `config/config.exs`.
3. [x] **Create `lib/chat_app/etl/sources/poshmark.ex`** — module skeleton.
4. [x] **Implement `parse_html/1`** — `Floki.parse_document!/1`; iterate `[data-id]` elements; extract each field using `Floki.find`, `Floki.attribute`, `Floki.text`. Build relative href into absolute URL with config base URL. Tests 1–11 go green.
5. [x] **Implement nil guards** — `Floki.find(el, ".listing__size") |> List.first()` then `if elem, do: Floki.text(elem) |> String.trim(), else: nil`. Tests 9–10 go green.
6. [x] **Run selector regression test** (test 12) — this is a fixture quality check, not an implementation check. If it fails, fix the fixture.
7. [x] **Implement `fetch_items/1`** — `Req.get` to Poshmark search URL; pass response body to `parse_html/1`. Tests 13–14 go green.
8. [x] **Handle error returns** — rescue `Req.TransportError` → `{:error, :timeout}`; non-2xx → `{:ok, []}`.
9. [x] **Run all 16 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/sources/poshmark_test.exs` — 16/16 green, zero skips
- Tests 1–12 (`parse_html/1` unit tests) pass with `async: true` when extracted — pure function, no I/O
- Selector regression test (12) is documented: if Poshmark changes HTML structure, this test fails fast with a specific selector name in the error message
- `grep -rn "poshmark.com" lib/chat_app/etl/sources/poshmark.ex` returns zero hardcoded URL hits (base URL comes from config)
- `Bypass.verify_expectations!/1` called in each integration test's `on_exit`
- `mix compile --warnings-as-errors` clean
- Known risk documented in module: CSS selectors are hardcoded; HTML drift will break parsing silently unless selector regression test is maintained
