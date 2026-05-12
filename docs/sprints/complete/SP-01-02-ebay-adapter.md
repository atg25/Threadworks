---
sprint_id: SP-01-02
phase: 1
status: complete
activated_date: 2026-05-06
completed_date: 2026-05-10
prerequisites: SP-01-01 complete
estimated_days: 1.5
---

# SP-01-02 — eBay Source Adapter

**Goal:** Implement the eBay source adapter with a GenServer-supervised ETS token cache and fully Bypass-verified HTTP, giving the pipeline a tested, isolated eBay data source.

---

## Scope

**In:**
- `lib/chat_app/etl/sources/ebay/token_cache.ex` — GenServer owning the ETS table; serializes token refresh to prevent thundering herd
- `lib/chat_app/etl/sources/ebay.ex` — public API: `get_token/0`, `fetch_items/1`
- Add `TokenCache` to `ChatApp.Application` supervision tree
- Add `:ebay_api_base_url`, `:ebay_app_id`, `:ebay_cert_id` config keys to `config/config.exs` and `config/test.exs`
- `test/chat_app/etl/sources/ebay_test.exs`
- `test/support/ebay_bypass_helper.ex` — shared setup: starts Bypass, sets application env, clears ETS

**Out:** Normalizer calls — the adapter returns raw eBay JSON maps exactly as decoded from the API; `Normalizer.normalize/2` (SP-01-01) handles field mapping. No Depop, no Poshmark, no ScrapeWorker wiring.

---

## Design Decision: GenServer + ETS

A plain ETS table has a TOCTOU race: two concurrent processes both read a stale token, both start an HTTP refresh, and two OAuth calls fire. `TokenCache` is a GenServer that owns the ETS table under a named supervised process. ETS reads bypass the GenServer (fast path — check expiry directly). Token writes and refreshes go through the GenServer (`call`), which serializes them. Inside `refresh_if_stale/0`, the GenServer re-reads ETS after acquiring the lock (double-checked locking) so at most one HTTP call fires per expiry window. Test 4 guards this explicitly.

---

## Configuration

Add to `config/config.exs`:
```elixir
config :chat_app, :ebay_api_base_url,
  System.get_env("EBAY_API_BASE_URL", "https://api.ebay.com")
config :chat_app, :ebay_app_id,   System.get_env("EBAY_APP_ID", "")
config :chat_app, :ebay_cert_id,  System.get_env("EBAY_CERT_ID", "")
```

Add to `config/test.exs`:
```elixir
config :chat_app, :ebay_app_id,  "test_app_id"
config :chat_app, :ebay_cert_id, "test_cert_id"
```

The test `setup` block overrides `:ebay_api_base_url` with `"http://localhost:#{bypass.port}"` for each test.

---

## Test Suite

**File:** `test/chat_app/etl/sources/ebay_test.exs`
**Case:** `use ExUnit.Case, async: false` — ETS is process-global; tests must run serially.

Each test's `setup`:
1. `bypass = Bypass.open()`
2. `Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")`
3. `ChatApp.ETL.Sources.Ebay.TokenCache.clear()`

### Unit Tests — token cache (no real HTTP; Bypass configured to 500 if called unexpectedly)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `get_token/0 returns cached token without HTTP when cache valid` | Seed ETS via `TokenCache.put("cached_token", far_future_datetime())`; configure Bypass to respond 500 if called | Returns `"cached_token"`; assert `Bypass` was never called (via `Bypass.expect` not matched) | Cache read path not implemented; always re-fetching token |
| 2 | `get_token/0 refreshes expired token and updates cache` | Seed ETS with `expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)`; Bypass `/identity/v1/oauth2/token` returns `%{"access_token" => "new_token", "expires_in" => 7200}` | Returns `"new_token"`; `TokenCache.get()` now returns `{"new_token", expires_at}` where `expires_at > DateTime.utc_now()` | Expired token still returned; ETS not updated after refresh |
| 3 | `get_token/0 fetches token when cache is empty` | `TokenCache.clear()` ensures ETS empty; Bypass returns `%{"access_token" => "fresh_token", "expires_in" => 3600}` | Returns `"fresh_token"` | `:ets.lookup` on empty table crashes; no base case for empty cache |
| 4 | `get_token/0 fires exactly one HTTP call under 10 concurrent callers` | `TokenCache.clear()`; Bypass token endpoint uses an `Agent` counter to count calls, sleeps 30ms before responding; `Enum.map(1..10, fn _ -> Task.async(fn -> Ebay.get_token() end) end) \|> Task.await_many(5000)` | Agent counter == 1; all 10 tasks return the same token string | Thundering herd: 10 parallel HTTP calls; TOCTOU in ETS check |
| 5 | `get_token/0 returns {:error, :missing_credentials} when app_id is empty string` | `Application.put_env(:chat_app, :ebay_app_id, "")`; Bypass configured to 500 | `{:error, :missing_credentials}` returned before any HTTP call | Silent empty-credential auth failure surfaces as cryptic 401 in production |

### Integration Tests — HTTP search (Bypass-mocked)

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 6 | `fetch_items/1 returns 50 raw maps preserving eBay nested JSON structure` | Seed valid token; Bypass returns full `ebay_search_response.json` fixture (50 items) | `{:ok, items}` where `length(items) == 50`; each item is a map with keys `"itemId"`, `"title"`, `"price"` (nested map), `"image"` (nested map), `"itemWebUrl"` exactly as decoded | Adapter flattens structure that Normalizer expects nested; limit param missing so API caps at default |
| 7 | `fetch_items/1 sends correct query string parameters` | Bypass captures `conn.query_string` | Contains `q=vintage+levi` (URL-encoded), `category_ids=15724%2C11450`, `limit=50` | Category IDs missing; limit hardcoded to wrong value; query not URL-encoded |
| 8 | `fetch_items/1 sends Bearer token in Authorization header` | Seed ETS with `"test_bearer_token"`; Bypass inspects `conn.req_headers` | Header `{"authorization", "Bearer test_bearer_token"}` present | Token not injected; wrong scheme (Basic vs Bearer); wrong header name |
| 9 | `fetch_items/1 returns {:error, :unauthorized} on 401` | Bypass returns `{401, [], Jason.encode!(%{"error" => "Invalid token"})}` | `{:error, :unauthorized}` — no exception raised; no crash | `Req` raises on 4xx; unhandled match error propagates |
| 10 | `fetch_items/1 returns {:ok, []} when itemSummaries is empty list` | Bypass returns `%{"total" => 0, "itemSummaries" => []}` | `{:ok, []}` | `Enum.map` on empty list returns `[]` — this should pass but guards accidental nil handling |
| 11 | `fetch_items/1 returns {:ok, []} when itemSummaries key is absent` | Bypass returns `%{"total" => 0}` (key missing) | `{:ok, []}` | `Map.fetch!` raises `KeyError`; pattern match on absent key |
| 12 | `fetch_items/1 returns {:error, :timeout} on network timeout` | `Bypass.expect(bypass, "GET", fn conn -> Process.sleep(10_000); conn end)` with `receive_timeout: 100` | `{:error, :timeout}` — not a raised exception | `Req.TransportError` propagates uncaught; Oban job crashes with non-retryable error |
| 13 | `fetch_items/1 uses :ebay_api_base_url from application config` | `Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")`; Bypass expects one GET request | Bypass receives the HTTP call | Base URL hardcoded in module; env var not read at call time |

### Integration Tests — OAuth token request format

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 14 | `token refresh sends client_credentials grant with form-encoded body` | Bypass captures `conn` on POST to `/identity/v1/oauth2/token`; read body | Body contains `grant_type=client_credentials` and `scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope` | Wrong grant type; scope missing; body sent as JSON instead of form |
| 15 | `token refresh sends Basic auth with base64(app_id:cert_id)` | Bypass captures Authorization header on token endpoint | Header is `"Basic " <> Base.encode64("test_app_id:test_cert_id")` | Bearer used on token endpoint; credentials not base64-encoded; separator wrong |

---

## Implementation Tasks (TDD Order)

1. [x] **Write all 15 tests** — all red. No implementation files created yet.
2. [x] **Add config keys** to `config/config.exs` and `config/test.exs` as shown above.
3. [x] **Create `lib/chat_app/etl/sources/ebay/token_cache.ex`** — GenServer skeleton. Implement `start_link/1`, `init/1` (creates ETS table with `:named_table, :public, read_concurrency: true`), `get/0` (direct ETS read, bypasses GenServer), `put/2` (GenServer cast, writes to ETS), `clear/0` (GenServer call, deletes all ETS entries — test helper). Tests 1–3 begin going green.
4. [x] **Implement `refresh_if_stale/0`** on `TokenCache` — serialized GenServer call. Inside the call handler: re-check ETS (double-checked lock); if still stale, make HTTP call to token endpoint, write result to ETS, return token. Test 4 goes green.
5. [x] **Add `TokenCache` to `Application` children** between Oban and Endpoint.
6. [x] **Implement `{:error, :missing_credentials}` guard** in `get_token/0` — read config before any ETS/HTTP call. Test 5 goes green.
7. [x] **Create `lib/chat_app/etl/sources/ebay.ex`** — `get_token/0` reads ETS directly; calls `TokenCache.refresh_if_stale/0` only when token absent or expired.
8. [x] **Implement `fetch_items/1`** — calls `get_token/0`; builds URL from `Application.get_env(:chat_app, :ebay_api_base_url)`; sends `Req.get` with query params and Authorization header; parses `Map.get(body, "itemSummaries", [])`.
9. [x] **Handle error returns** — `rescue Req.TransportError` → `{:error, :timeout}`; match `%Req.Response{status: 401}` → `{:error, :unauthorized}`.
10. [x] **Implement token endpoint** in private `do_refresh_token/0` — `Req.post` with Basic auth header, form-encoded body, parse `access_token` and `expires_in` from response.
11. [x] **Run all 15 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/sources/ebay_test.exs` — 15/15 green, zero skips
- Test 4 assertion: Agent counter checked, not wall-clock timing
- `TokenCache` present in `Application` supervision tree; `mix run --no-halt` starts without error
- `grep -rn "api.ebay.com\|api.sandbox.ebay.com" lib/chat_app/etl/` returns zero hardcoded URL hits
- `mix test test/chat_app/etl/sources/ebay_test.exs` passes with no outbound network calls (`Bypass.verify_expectations!/1` called in each test's `on_exit`)
- `mix compile --warnings-as-errors` clean
- `TokenCache.clear/0` documented as `@doc false`; decision recorded: it is a public function required for test isolation, compiled in all envs
