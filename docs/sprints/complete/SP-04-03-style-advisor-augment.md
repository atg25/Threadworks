---
id: SP-04-03
phase: 4
slug: style-advisor-augment
status: complete
created: 2026-05-12
activated_date: 2026-05-12
completed_date: 2026-05-12
estimated_days: 1
depends_on:
  - SP-04-01
---

# SP-04-03 — StyleAdvisor.augment/1 with Token Budget

**Goal:** Implement `StyleAdvisor.augment/2`, wiring `HybridEngine.search/1` to `build_prompt/2` with a token-budget cap and a hardened error fallback, fully tested against a mocked engine.

---

## Scope

### In

- `lib/chat_app/ai/style_advisor.ex` — `augment/2` (adds to the module started in SP-04-01)
- `lib/chat_app/search/hybrid_engine_behaviour.ex` — behaviour module (if not already present)
- `test/unit/ai/style_advisor_test.exs` (augment/2 section)
- `test/integration/ai/style_advisor_integration_test.exs`
- `test/e2e/sp_04_03_augment_e2e_test.exs` (tagged `:e2e`, excluded from default CI)

### Out

- `HybridEngine` implementation (Phase 2, complete)
- `ResponseParser`, `QueryUnderstander` (other sprints)
- LiveView (SP-04-04)

---

## Design Decisions Locked

**Token budget is a caller-supplied parameter, not a DB read inside `augment/2`.**

Rationale: keeping `augment/2` free of DB calls makes it testable without Ecto and keeps the ChatLive process responsible for the context it already owns (`conversation_id`). ChatLive will read `usage_records` and pass the total before calling `augment/2`.

```elixir
@spec augment(user_message :: String.t(), opts :: keyword()) ::
        {:ok, augmented_prompt :: String.t(), items :: [%ClothingItem{}]}

# opts:
#   conversation_tokens: non_neg_integer()  (default: 0)
```

**Default item cap: 10.** When `conversation_tokens <= 3000`, return up to 10 items.

**Budget cap: 8.** When `conversation_tokens > 3000`, cap at 8 items.

**HybridEngine error fallback:** if `HybridEngine.search/1` returns `{:error, reason}`, log the error and return `{:ok, base_system_prompt, []}`. Never propagate the error to the caller.

**Empty results:** if `HybridEngine.search/1` returns `{:ok, []}`, return `{:ok, base_system_prompt, []}` — do not inject an empty `AVAILABLE ITEMS` block.

**Base system prompt:** a module-level constant string (e.g., `@base_system_prompt "You are Threadworks AI, a style consultant specialising in second-hand clothing."`). Defined once in `style_advisor.ex`.

**HybridEngine indirection:** `augment/2` calls the engine via `Application.get_env(:chat_app, :hybrid_engine_module, ChatApp.Search.HybridEngine)`. Test env configures `ChatApp.Search.MockHybridEngine` (Mox).

---

## Tests

### E2E — Live integration (tagged `:e2e`; excluded from default CI run)

**Blocked on:** Phase 2 complete (SP-02-05b), items seeded in DB with embeddings.

Run with: `mix test --include e2e`

---

**E1 — Live search returns results for a known clothing query**

```elixir
# Requires seeded DB with at least one embedded ClothingItem
{:ok, prompt, items} = StyleAdvisor.augment("vintage denim jacket")
assert String.contains?(prompt, "AVAILABLE ITEMS:")
assert length(items) > 0
assert Enum.all?(items, &match?(%ClothingItem{}, &1))
```

Failure guarded: live HybridEngine integration broken; `augment/2` not calling
`build_prompt/2` with real results.

---

**E2 — Live search returns no results for a nonsense query**

```elixir
{:ok, prompt, items} = StyleAdvisor.augment("xyzzy foobar nonsense query 99999")
assert items == []
refute String.contains?(prompt, "AVAILABLE ITEMS:")
```

Failure guarded: empty result crashing the pipeline or injecting a useless
empty block into the prompt.

---

### Integration — HybridEngine mocked via Mox

All tests in `test/integration/ai/style_advisor_integration_test.exs`.

Setup:
```elixir
import Mox
setup :verify_on_exit!
```

---

**I1 — augment/2 passes the user message verbatim to HybridEngine.search**

```elixir
expect(MockHybridEngine, :search, fn "blue jeans" -> {:ok, [item_fixture()]} end)
{:ok, _prompt, _items} = StyleAdvisor.augment("blue jeans")
```

Mox will raise if the argument doesn't match. Failure guarded: wrong argument
forwarded, query mangled before being passed to search.

---

**I2 — augment/2 calls build_prompt when results are non-empty**

```elixir
items = [item_fixture()]
expect(MockHybridEngine, :search, fn _ -> {:ok, items} end)
{:ok, prompt, returned_items} = StyleAdvisor.augment("blue jeans")
assert String.contains?(prompt, "AVAILABLE ITEMS:")
assert String.contains?(prompt, "[1]")
assert returned_items == items
```

Failure guarded: search results not forwarded to `build_prompt/2`; augment
returning raw results without injecting the prompt block.

---

**I3 — augment/2 returns base prompt when search is empty**

```elixir
expect(MockHybridEngine, :search, fn _ -> {:ok, []} end)
{:ok, prompt, items} = StyleAdvisor.augment("anything")
assert items == []
refute String.contains?(prompt, "AVAILABLE ITEMS:")
assert String.starts_with?(prompt, "You are Threadworks AI")
```

Failure guarded: calling `build_prompt/2` with an empty list and injecting a
malformed empty items block.

---

**I4 — Token budget: 10 items capped to 8 when conversation_tokens > 3000**

```elixir
fifteen_items = for i <- 1..15, do: %ClothingItem{item_fixture() | id: i, rrf_score: 0.02}
expect(MockHybridEngine, :search, fn _ -> {:ok, fifteen_items} end)
{:ok, _prompt, items} = StyleAdvisor.augment("summer dress", conversation_tokens: 3001)
assert length(items) == 8
```

Failure guarded: token guard not triggering; off-by-one on the 3000 threshold
(`> 3000` vs `>= 3000`).

---

**I5 — Token budget: 10 items NOT capped when conversation_tokens <= 3000**

```elixir
fifteen_items = for i <- 1..15, do: %ClothingItem{item_fixture() | id: i, rrf_score: 0.02}
expect(MockHybridEngine, :search, fn _ -> {:ok, fifteen_items} end)
{:ok, _prompt, items} = StyleAdvisor.augment("summer dress", conversation_tokens: 3000)
assert length(items) == 10
```

Failure guarded: cap applied even when budget is not exceeded; `>=` instead of `>`.

---

**M1 — HybridEngine error returns {:ok, base_prompt, []} without crashing**

```elixir
expect(MockHybridEngine, :search, fn _ -> {:error, :timeout} end)
{:ok, prompt, items} = StyleAdvisor.augment("query")
assert items == []
refute String.contains?(prompt, "AVAILABLE ITEMS:")
```

Failure guarded: `{:error, :timeout}` tuple crashing a `{:ok, results} = ...`
pattern match, taking down the LiveView process mid-conversation.

---

### Unit

In `test/unit/ai/style_advisor_test.exs`, describe block `"augment/2"`.

---

**M2 — Default 10-item cap applied when no budget pressure**

```elixir
stub(MockHybridEngine, :search, fn _ ->
  items = for i <- 1..12, do: %ClothingItem{item_fixture() | id: i}
  {:ok, items}
end)
{:ok, _prompt, items} = StyleAdvisor.augment("query")   # no conversation_tokens opt
assert length(items) == 10
```

Failure guarded: no default cap, allowing all HybridEngine results to be injected
regardless of count, silently blowing the context window.

---

## Implementation Tasks

- [x] Write all tests (E1–E2, I1–I5, M1–M2) — all failing
- [x] Add `ChatApp.Search.HybridEngineBehaviour` with `@callback search(String.t()) :: {:ok, [%ClothingItem{}]} | {:error, term()}`
- [x] Configure `HybridEngine` indirection: `Application.get_env(:chat_app, :hybrid_engine_module, ChatApp.Search.HybridEngine)`
- [x] Add Mox to `mix.exs` dev/test deps if not already present: `{:mox, "~> 1.0", only: :test}`
- [x] Declare `MockHybridEngine` in `test/support/mocks.ex`: `Mox.defmock(ChatApp.Search.MockHybridEngine, for: ChatApp.Search.HybridEngineBehaviour)`
- [x] Set `config :chat_app, :hybrid_engine_module, ChatApp.Search.MockHybridEngine` in `config/test.exs`
- [x] Implement `augment/2` in `lib/chat_app/ai/style_advisor.ex`
  - [x] Default opts: `conversation_tokens: 0`
  - [x] Call `hybrid_engine_module().search(user_message)`
  - [x] On `{:ok, []}`: return `{:ok, @base_system_prompt, []}`
  - [x] On `{:ok, results}`: apply cap (8 if `conversation_tokens > 3000`, else 10); call `build_prompt(@base_system_prompt, capped_items)`; return `{:ok, prompt, capped_items}`
  - [x] On `{:error, reason}`: log warning with `Logger.warning/2`; return `{:ok, @base_system_prompt, []}`
- [x] Run `mix test test/unit/ai/style_advisor_test.exs test/integration/ai/style_advisor_integration_test.exs` — all green
- [x] Verify E2E tests pass with seeded DB: `mix test --include e2e test/e2e/sp_04_03_augment_e2e_test.exs`

---

## Definition of Done

- [x] All 9 non-E2E tests pass (`mix test test/unit/ai/style_advisor_test.exs test/integration/ai/style_advisor_integration_test.exs`)
- [x] E2E tests pass on seeded DB (`mix test --include e2e test/e2e/sp_04_03_augment_e2e_test.exs`)
- [x] `augment/2` never raises or returns an error tuple — all error paths return `{:ok, base_prompt, []}`
- [x] Token budget API shape documented in module `@moduledoc`: parameter, default, cap values
- [x] `mix test` full suite green — zero regressions

## Implementation Notes

**E2E test design (decided during implementation):** The sprint spec described E1/E2 as blocked on "items seeded in DB with embeddings" and a live OpenAI key. Every other E2E search test in this codebase (SP-02-03, SP-02-05a, SP-02-05b) uses Bypass to stub the OpenAI embedder instead of requiring a live key. The SP-04-03 E2E tests follow the same pattern: Bypass stubs the embedder, `VectorStore.upsert` + `FTS5Index.upsert` seed the test DB, and a `setup` block swaps `Application.get_env(:chat_app, :hybrid_engine_module)` back to the real `HybridEngine` for the duration of each test (the test env config defaults to `MockHybridEngine`). This makes E1/E2 self-contained, deterministic, and runnable in CI without a live API key.

**Carry-forward risk — `build_prompt/2` unknown source label:** `build_prompt/2` uses `Map.fetch!(@source_labels, ...)` which raises `KeyError` if `item.source` is not one of `"ebay"`, `"depop"`, or `"poshmark"`. The `{:ok, results}` branch of `augment/2` has no rescue around `build_prompt/2`, so this would crash the LiveView process. Safe today because the ETL layer is closed over exactly those three sources. **If a new scraper source is added, `@source_labels` in `lib/chat_app/ai/style_advisor.ex` must be updated at the same time.** Documented in `docs/phases/phase-4-chat-rag.md` Risks section.
