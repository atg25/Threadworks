---
sprint_id: SP-01-03
phase: 1
status: complete
activated_date: 2026-05-10
completed_date: 2026-05-10
prerequisites: SP-01-01 complete
estimated_days: 1
---

# SP-01-03 — Depop Source Adapter

**Goal:** Implement the Depop source adapter with Bypass-mocked JSON endpoint and required scraper headers, so the pipeline has a tested, isolated Depop data source with correct rate-limit and nil-field handling.

---

## Scope

**In:**
- `lib/chat_app/etl/sources/depop.ex` — public API: `fetch_items/1`
- Add `:depop_api_base_url` config key to `config/config.exs` and `config/test.exs`
- `test/chat_app/etl/sources/depop_test.exs`

**Out:** Normalizer calls — adapter returns raw string-keyed maps as decoded from Depop's JSON. No OAuth, no ETS, no ScrapeWorker wiring. Poshmark adapter is a separate sprint.

---

## Configuration

Add to `config/config.exs`:
```elixir
config :chat_app, :depop_api_base_url,
  System.get_env("DEPOP_API_BASE_URL", "https://api.depop.com")
```

Add to `config/test.exs`:
```elixir
# no override needed — test setup puts Bypass URL via Application.put_env
```

---

## Interface Contract

`fetch_items/1` accepts a query string and returns `{:ok, [raw_map]}` or `{:error, reason}`.

Each raw map is a string-keyed map matching Depop's decoded JSON structure:
`"id"`, `"description"`, `"displayedPrice"`, `"brand"`, `"sizes"` (list), `"pictureUrl"`, `"slug"`

The Normalizer's `normalize("depop", raw)` handles all field mapping. The adapter does not reshape or transform the decoded JSON, except it must guard against nil `sizes` (see tests 9–10) by passing through the raw value as-is; nil handling lives in the Normalizer.

> **Note:** The `displayedPrice` field can carry a currency symbol prefix in non-US responses (e.g. `"£12.00"`). The adapter returns the raw string. The Normalizer is responsible for stripping the symbol. Test 12 guards this adapter-level pass-through (the adapter must not crash on a non-numeric string).

---

## Test Suite

**File:** `test/chat_app/etl/sources/depop_test.exs`
**Case:** `use ExUnit.Case, async: false`

Each test's `setup`:
1. `bypass = Bypass.open()`
2. `Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{bypass.port}")`

### Integration Tests (Bypass-mocked)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `fetch_items/1 returns one raw map per product in fixture` | Bypass returns `depop_search_response.json` fixture | `{:ok, items}` where `length(items) == 24`; each element is a map | Response key wrong (e.g. `"results"` vs `"products"`); nested unwrap missing |
| 2 | `fetch_items/1 raw maps preserve all required Depop keys` | Bypass returns fixture; inspect first item | Each map has keys `"id"`, `"description"`, `"displayedPrice"`, `"brand"`, `"sizes"`, `"pictureUrl"`, `"slug"` | Key renamed during decode; atom keys used instead of string keys (Normalizer expects string keys) |
| 3 | `fetch_items/1 sends User-Agent: Mozilla/5.0 header` | Bypass inspects `conn.req_headers` | `{"user-agent", "Mozilla/5.0"}` present in headers | Header missing; rate-limited in production |
| 4 | `fetch_items/1 sends Accept-Language: en-US header` | Bypass inspects `conn.req_headers` | `{"accept-language", "en-US"}` present in headers | Header missing; locale-specific responses break field extraction |
| 5 | `fetch_items/1 builds URL with q and limit=24 query params` | Bypass captures `conn.query_string` | Contains `q=vintage+levi` and `limit=24` | Query string malformed; limit wrong value; query not URL-encoded |
| 6 | `fetch_items/1 returns {:ok, []} when products list is empty` | Bypass returns `%{"products" => []}` | `{:ok, []}` | Nil match on empty list; wrong key name |
| 7 | `fetch_items/1 returns {:error, :rate_limited} on 429` | Bypass returns `{429, [], ""}` | `{:error, :rate_limited}` — no exception raised | Unhandled 429 crashes with MatchError; Oban marks job as failed without retry |
| 8 | `fetch_items/1 returns {:error, :timeout} on network timeout` | Bypass closes connection before responding; `receive_timeout: 100` in test config | `{:error, :timeout}` — not a raised exception | `Req.TransportError` propagates uncaught |
| 9 | `fetch_items/1 passes through sizes: [] without crash` | Bypass returns fixture with one item where `"sizes": []` | That item's map has `"sizes": []` | Adapter crashes trying to access `sizes[0]`; nil returned instead of empty list |
| 10 | `fetch_items/1 passes through sizes: null without crash` | Bypass returns fixture with one item where `"sizes": null` | That item's map has `"sizes": nil` | Adapter crashes on nil list; Enum.at raises |
| 11 | `fetch_items/1 passes through nil pictureUrl without crash` | Bypass returns fixture item with `"pictureUrl": null` | That item's map has `"pictureUrl": nil` | nil coerced to empty string; crash on nil string operation |
| 12 | `fetch_items/1 passes through non-numeric displayedPrice without crash` | Bypass returns fixture item with `"displayedPrice": "£12.00"` | That item's map has `"displayedPrice": "£12.00"` | Adapter attempts `Decimal.new("£12.00")` and crashes; currency symbol handling belongs in Normalizer |
| 13 | `fetch_items/1 uses :depop_api_base_url from application config` | `Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{bypass.port}")`; Bypass expects one GET | Bypass receives call | Base URL hardcoded; env var ignored |

---

## Implementation Tasks (TDD Order)

- [x] **Write all 13 tests** — all red.
- [x] **Add `:depop_api_base_url` config key** to `config/config.exs`.
- [x] **Create `lib/chat_app/etl/sources/depop.ex`** — module skeleton with `fetch_items/1` returning `{:error, :not_implemented}`.
- [x] **Implement HTTP call** — `Req.get` with User-Agent and Accept-Language headers; URL built from `Application.get_env(:chat_app, :depop_api_base_url)`. Tests 3–5 go green.
- [x] **Implement response parsing** — `Map.get(body, "products", [])` to unwrap list. Tests 1–2 go green.
- [x] **Handle nil and empty `sizes`** — pass raw value through unchanged. Tests 9–10 go green.
- [x] **Handle nil `pictureUrl`** — pass raw value through unchanged. Test 11 goes green.
- [x] **Handle non-numeric `displayedPrice`** — pass raw value through unchanged. Test 12 goes green.
- [x] **Handle error returns** — match `{:ok, %Req.Response{status: 429}}` → `{:error, :rate_limited}`; rescue `Req.TransportError` → `{:error, :timeout}`.
- [x] **Run all 13 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/sources/depop_test.exs` — 13/13 green, zero skips
- `grep -rn "api.depop.com" lib/chat_app/etl/sources/depop.ex` returns zero hardcoded URL hits
- `Bypass.verify_expectations!/1` called in each test's `on_exit`; no outbound calls to real Depop API during `mix test`
- `mix compile --warnings-as-errors` clean
- Adapter makes no attempt to parse, transform, or validate field values — raw JSON maps only
