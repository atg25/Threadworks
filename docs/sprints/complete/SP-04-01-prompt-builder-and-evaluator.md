---
id: SP-04-01
phase: 4
slug: prompt-builder-and-evaluator
status: complete
created: 2026-05-12
completed_date: 2026-05-12
estimated_days: 1
depends_on: []
---

# SP-04-01 — Prompt Builder and Query Evaluator

**Goal:** Implement `StyleAdvisor.build_prompt/2` and `QueryUnderstander.evaluate/1` as fully-tested pure functions with no side effects.

---

## Scope

### In

- `lib/chat_app/ai/style_advisor.ex` — `build_prompt/2` only
- `lib/chat_app/ai/query_understander.ex` — `evaluate/1`
- `test/unit/ai/style_advisor_test.exs` (build_prompt/2 section)
- `test/unit/ai/query_understander_test.exs`

### Out

- `StyleAdvisor.augment/1` (SP-04-03)
- `ResponseParser` (SP-04-02)
- Any LiveView changes (SP-04-04)
- HybridEngine calls

---

## Design Decisions Locked

- `build_prompt/2` appends the `AVAILABLE ITEMS` block **after** the base prompt; the base is always first in the returned string.
- Item line format (exact): `[N] {name} | Size: {size} | Condition: {condition_string} | ${price} | {source_label}`
  - `condition_string`: atom stringified as-is (`Atom.to_string/1`): `:good → "good"`, `:like_new → "like_new"`
  - `source_label`: `:ebay → "eBay"`, `:depop → "Depop"`, `:poshmark → "Poshmark"`
  - `price`: formatted as two decimal places, e.g. `"45.00"` (use `Decimal.to_string/1` then zero-pad or format with `:io_lib`)
- `evaluate/1` returns `{:recommend, items}` where `items` is the **full input list**, not the filtered subset.
- `@min_rrf_score 0.015` — uses `>=` (inclusive).
- `@min_results 2` — uses `>=` (inclusive).

---

## Tests

### Unit — `StyleAdvisor.build_prompt/2`

All tests in `test/unit/ai/style_advisor_test.exs`, describe block `"build_prompt/2"`.

---

**U1 — AVAILABLE ITEMS header is present**

```elixir
item = %ClothingItem{name: "Levi's 501", size: "28x30", condition: :good,
                     price: Decimal.new("45.00"), source: :ebay}
result = StyleAdvisor.build_prompt("base", [item])
assert String.contains?(result, "AVAILABLE ITEMS:")
```

Failure guarded: items block never appended to the string.

---

**U2 — Exactly N item lines with correct format**

```elixir
items = [
  %ClothingItem{name: "Levi's 501",    size: "28x30", condition: :good,      price: Decimal.new("45.00"), source: :ebay},
  %ClothingItem{name: "CK Blazer",     size: "M",     condition: :like_new,  price: Decimal.new("78.00"), source: :depop},
  %ClothingItem{name: "Floral Blouse", size: "S",     condition: :fair,      price: Decimal.new("22.00"), source: :poshmark}
]
result = StyleAdvisor.build_prompt("base", items)
lines = String.split(result, "\n")
item_lines = Enum.filter(lines, &Regex.match?(~r/^\[\d+\]/, &1))
assert length(item_lines) == 3
```

Failure guarded: item serialization failing silently, wrong line count.

---

**U3 — Base prompt appears before AVAILABLE ITEMS block**

```elixir
base = "You are a style advisor."
item = %ClothingItem{name: "Jeans", size: "M", condition: :good,
                     price: Decimal.new("30.00"), source: :ebay}
result = StyleAdvisor.build_prompt(base, [item])
base_pos     = :binary.match(result, base) |> elem(0)
items_pos    = :binary.match(result, "AVAILABLE ITEMS:") |> elem(0)
assert base_pos < items_pos
```

Failure guarded: items block prepended in front of or in place of base prompt.

---

**U4 — Item numbering is 1-based and sequential**

```elixir
items = for _ <- 1..3, do: %ClothingItem{name: "X", size: "M", condition: :good,
                                          price: Decimal.new("10.00"), source: :ebay}
result = StyleAdvisor.build_prompt("base", items)
assert String.contains?(result, "[1]")
assert String.contains?(result, "[2]")
assert String.contains?(result, "[3]")
refute String.contains?(result, "[0]")
refute String.contains?(result, "[4]")
```

Failure guarded: off-by-one in `Enum.with_index/1` base argument.

---

**U5 — Empty items list does not crash; produces zero item lines**

```elixir
result = StyleAdvisor.build_prompt("base", [])
assert String.contains?(result, "AVAILABLE ITEMS:")
lines = String.split(result, "\n")
item_lines = Enum.filter(lines, &Regex.match?(~r/^\[\d+\]/, &1))
assert item_lines == []
```

Failure guarded: crash on empty list; empty block injecting a stray `[0]` line.

---

**U6 — JSON instruction block present with exact spec wording**

```elixir
item = %ClothingItem{name: "Jeans", size: "M", condition: :good,
                     price: Decimal.new("30.00"), source: :ebay}
result = StyleAdvisor.build_prompt("base", [item])
assert String.contains?(result, "After your response, output a JSON block:")
assert String.contains?(result, ~s({"cards": [{"item_id":))
assert String.contains?(result, "Only include items you actually recommend.")
```

Failure guarded: instruction text truncated or reformatted, causing the LLM to never
emit parseable card JSON.

---

**M1 — Full item line contains all five fields in correct order**

```elixir
item = %ClothingItem{name: "Levi's 501 Jeans", size: "28x30", condition: :good,
                     price: Decimal.new("45.00"), source: :ebay}
result = StyleAdvisor.build_prompt("base", [item])
assert Regex.match?(
  ~r/\[1\] Levi's 501 Jeans \| Size: 28x30 \| Condition: good \| \$45\.00 \| eBay/,
  result
)
```

Failure guarded: missing price or source fields; wrong field order; source atom not
mapped to human label; price not formatted to 2 decimal places.

---

### Unit — `QueryUnderstander.evaluate/1`

All tests in `test/unit/ai/query_understander_test.exs`, describe block `"evaluate/1"`.

---

**U7 — Returns :clarify for empty list**

```elixir
assert {:clarify, msg} = QueryUnderstander.evaluate([])
assert is_binary(msg) and msg != ""
```

Failure guarded: crash or nil return on empty input.

---

**U8 — Returns :clarify when all items below threshold**

```elixir
items = [
  %ClothingItem{rrf_score: 0.008},
  %ClothingItem{rrf_score: 0.010}
]
assert {:clarify, _} = QueryUnderstander.evaluate(items)
```

Failure guarded: threshold boundary off (comparing against 0.014 or 0.016 instead of 0.015).

---

**U9 — Returns :clarify when exactly one item meets threshold**

```elixir
items = [%ClothingItem{rrf_score: 0.02}, %ClothingItem{rrf_score: 0.008}]
assert {:clarify, _} = QueryUnderstander.evaluate(items)
```

Failure guarded: count check using `>` instead of `>=` on `@min_results`; treating 1
qualifying item as sufficient.

---

**U10 — Returns :recommend when exactly two items meet threshold**

```elixir
items = [%ClothingItem{rrf_score: 0.02}, %ClothingItem{rrf_score: 0.02}]
assert {:recommend, ^items} = QueryUnderstander.evaluate(items)
```

Failure guarded: off-by-one leaving two qualifying items returning :clarify.

---

**U11 — Returns :recommend at exact threshold boundary (0.015)**

```elixir
items = [%ClothingItem{rrf_score: 0.015}, %ClothingItem{rrf_score: 0.015}]
assert {:recommend, _} = QueryUnderstander.evaluate(items)
```

Failure guarded: `>=` implemented as `>`, dropping items exactly at the threshold.

---

**U12 — :recommend returns the full input list, not the filtered high-relevance subset**

```elixir
items = [
  %ClothingItem{rrf_score: 0.02},
  %ClothingItem{rrf_score: 0.02},
  %ClothingItem{rrf_score: 0.001}  # below threshold — must still be in result
]
assert {:recommend, returned} = QueryUnderstander.evaluate(items)
assert length(returned) == 3
assert Enum.any?(returned, &(&1.rrf_score == 0.001))
```

Failure guarded: implementation returning `high_relevance` (the filtered list) instead
of the full `items` argument — silently dropping lower-scored but still useful results
passed to the LLM.

---

**M2 — :recommend fires with exactly 2 qualifying items among a 10-item list**

```elixir
high  = [%ClothingItem{rrf_score: 0.02}, %ClothingItem{rrf_score: 0.016}]
low   = List.duplicate(%ClothingItem{rrf_score: 0.005}, 8)
items = high ++ low
assert {:recommend, returned} = QueryUnderstander.evaluate(items)
assert length(returned) == 10
```

Failure guarded: off-by-one in the filter or count check under realistic HybridEngine
result set sizes.

---

## Implementation Tasks

- [x] Write all unit tests (U1–U6, M1) in `test/unit/ai/style_advisor_test.exs` — all failing
- [x] Write all unit tests (U7–U12, M2) in `test/unit/ai/query_understander_test.exs` — all failing
- [x] Create `lib/chat_app/ai/style_advisor.ex` with `build_prompt/2`
  - [x] Append `AVAILABLE ITEMS:` block after base prompt
  - [x] Map each item to `[N] {name} | Size: {size} | Condition: {condition} | ${price} | {source_label}` (1-based index)
  - [x] Map source atoms: `:ebay → "eBay"`, `:depop → "Depop"`, `:poshmark → "Poshmark"`
  - [x] Format price to 2 decimal places
  - [x] Append JSON instruction block (exact wording from spec)
- [x] Create `lib/chat_app/ai/query_understander.ex` with `evaluate/1`
  - [x] `@min_rrf_score 0.015`
  - [x] `@min_results 2`
  - [x] Filter high_relevance with `>=` on both constants
  - [x] Return `{:recommend, items}` — the full input list, not `high_relevance`
  - [x] Return `{:clarify, "Could you tell me more? ..."}` (exact string from spec)
- [x] Run `mix test test/unit/ai/style_advisor_test.exs test/unit/ai/query_understander_test.exs` — all green

---

## Definition of Done

- [x] All 14 unit tests pass (`mix test test/unit/ai/`)
- [x] No E2E or integration tests in this sprint
- [x] `mix test` full suite green — zero regressions (2 pre-existing failures unrelated to this sprint: sprint-17 CSS class regression and sprint-14 compiler warning test)
- [x] Both modules are pure functions: no `Repo` calls, no HTTP calls, no side effects
- [x] `build_prompt/2` and `evaluate/1` are the only public functions in their respective modules (no premature exports)
