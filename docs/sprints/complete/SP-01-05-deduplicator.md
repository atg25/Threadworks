---
sprint_id: SP-01-05
phase: 1
status: complete
activated_date: 2026-05-11
completed_date: 2026-05-11
prerequisites: SP-01-01 complete (ClothingItem schema updated)
estimated_days: 1
actual_days: 1
---

# SP-01-05 — Deduplicator + Price History

**Goal:** Implement `Deduplicator.upsert/1` and `upsert_all/1` with Ecto's `on_conflict` semantics and always-write price history, so re-running the same scrape produces idempotent item counts and a growing price audit trail.

---

## Scope

**In:**
- `lib/chat_app/etl/deduplicator.ex` — `upsert/1`, `upsert_all/1`
- `test/chat_app/etl/deduplicator_test.exs`

**Out:** Workers, scheduler, adapters. This sprint only exercises the DB layer. No HTTP, no Oban jobs. Test fixtures are built inline (no factory library).

---

## Upsert Contract

```elixir
Repo.insert(changeset,
  on_conflict: {:replace, [:price, :last_scraped_at, :image_url, :size, :condition_normalized]},
  conflict_target: [:source, :source_id]
)
```

Fields **never** overwritten on conflict: `title`, `brand`, `url`, `source`, `source_id`, `inserted_at`.

One `PriceHistory` row is written per `upsert/1` call **regardless** of whether the price changed. This is the spec's explicit requirement and the most common point of implementation divergence (developers interpret "price history" as "log on change").

`upsert_all/1` accepts a list of normalized maps, calls `upsert/1` for each, and returns `{:ok, items}` where `items` is the list of persisted `%ClothingItem{}` structs (including DB-assigned `id` fields — required by ScrapeWorker to build EmbedWorker job args).

---

## Test Suite

**File:** `test/chat_app/etl/deduplicator_test.exs`
**Case:** `use ChatApp.DataCase` — all tests require DB sandbox

### Unit Tests — single upsert

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 1 | `upsert/1 inserts new item and returns {:ok, %ClothingItem{}}` | `upsert(valid_attrs())` where attrs include all required fields | `{:ok, %ClothingItem{id: id}}` where `id` is non-nil integer | Function returns wrong shape; DB insert fails on missing field |
| 2 | `upsert/1 on conflict replaces price` | `upsert(attrs with price: "10.00")`; `upsert(same source+source_id, price: "15.00")` | Second `{:ok, item}` has `item.price == Decimal.new("15.00")` | `on_conflict` target wrong; price not in replace list |
| 3 | `upsert/1 on conflict replaces image_url, size, condition_normalized, last_scraped_at` | Two upserts; second has different values for all four fields | Second item reflects new values for all four | Field missing from replace list |
| 4 | `upsert/1 on conflict does NOT replace title` | First upsert: `title: "Original Title"`; second upsert: `title: "Changed Title"` (same source+source_id) | DB row still has `title: "Original Title"` after second upsert | Title in replace list (should not be) |
| 5 | `upsert/1 second call same source+source_id does not increase item count` | `upsert(attrs)`; `count = count_items()`; `upsert(same source+source_id)`; `count2 = count_items()` | `count == count2` | on_conflict not wired; duplicate row inserted; unique constraint error raised |
| 6 | `upsert/1 does not raise on duplicate source+source_id` | Two identical upserts | No exception raised; both return `{:ok, _}` | `Repo.insert!` used instead of `Repo.insert`; `:raise` on_conflict_action |

### Unit Tests — price history

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 7 | `upsert/1 writes one PriceHistory row on first insert` | `upsert(valid_attrs())` | `Repo.aggregate(PriceHistory, :count) == 1` | Price history insert skipped entirely |
| 8 | `upsert/1 writes PriceHistory row even when price unchanged` | `upsert(attrs)`; `upsert(same item, same price)` | `Repo.aggregate(PriceHistory, :count) == 2` | Price history only written on price change (wrong interpretation of spec) |
| 9 | `upsert/1 writes PriceHistory row when price changes` | `upsert(attrs, price: "10.00")`; `upsert(same item, price: "12.00")` | `Repo.aggregate(PriceHistory, :count) == 2`; second row has `price: Decimal.new("12.00")` | Price history not written on update; only first insert logged |
| 10 | `PriceHistory row references correct item_id` | `{:ok, item} = upsert(attrs)` | `Repo.get_by!(PriceHistory, item_id: item.id)` does not raise | Foreign key wrong; item.id not passed to price_history insert |
| 11 | `upsert/1 handles nil image_url without constraint error` | `upsert(Map.put(valid_attrs(), :image_url, nil))` | `{:ok, %ClothingItem{image_url: nil}}` | NOT NULL constraint fired on nullable column |

### Integration Tests — batch upsert

| # | Test name | Inputs | Expected output | Failure mode guarded |
|---|---|---|---|---|
| 12 | `upsert_all/1 on N items: item count == N, price_history count == N` | `upsert_all(build_items(20))` | `count_items() == 20` AND `count_price_history() == 20` | One item fails silently; price_history skipped for batch |
| 13 | `upsert_all/1 on N items twice: item count unchanged, price_history count == 2N` | `upsert_all(same 20 items)`; `upsert_all(same 20 items)` | `count_items() == 20` AND `count_price_history() == 40` | Idempotency broken; price_history written once per item across all runs |
| 14 | `upsert_all/1 returns list of %ClothingItem{} with DB-assigned ids` | `{:ok, items} = upsert_all(build_items(5))` | `length(items) == 5`; every `item.id` is non-nil integer | Returns normalized maps not structs; ids nil (ScrapeWorker can't build EmbedWorker args) |
| 15 | `upsert_all/1 second run updates last_scraped_at on all items` | `upsert_all(items)`; `t1 = fetch_all_last_scraped_at()`; `upsert_all(same items with new last_scraped_at)`; `t2 = fetch_all_last_scraped_at()` | Every timestamp in `t2` is greater than corresponding timestamp in `t1` | `last_scraped_at` not in replace list; stale timestamp |

---

## Test Helpers (inline, no factory library)

```elixir
defp valid_attrs(overrides \\ %{}) do
  Map.merge(%{
    source: "ebay",
    source_id: "v1|#{System.unique_integer([:positive])}",
    title: "Vintage Levi's 501",
    brand: "Levi's",
    price: Decimal.new("24.99"),
    url: "https://ebay.com/item/123",
    condition_normalized: "good",
    last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second)
  }, overrides)
end

defp build_items(n) do
  Enum.map(1..n, fn i ->
    valid_attrs(%{source_id: "v1|#{i}", title: "Item #{i}"})
  end)
end
```

---

## Implementation Tasks (TDD Order)

1. ✅ **Write all 15 tests** — all red.
2. ✅ **Create `lib/chat_app/etl/deduplicator.ex`** — module skeleton with `upsert/1` and `upsert_all/1` returning `{:error, :not_implemented}`.
3. ✅ **Implement `upsert/1`** — build `ClothingItem.changeset/2`; call `Repo.insert` with `on_conflict` and `conflict_target` per spec; return `{:ok, item}` or `{:error, changeset}`. Tests 1–6 go green.
4. ✅ **Implement price history write** — after successful upsert, `Repo.insert!(%PriceHistory{item_id: item.id, price: item.price})`. Tests 7–11 go green.
5. ✅ **Implement `upsert_all/1`** — `Enum.map(items, &upsert/1)`; collect successes; return `{:ok, items}`. Tests 12–15 go green.
6. ✅ **Run all 15 tests until green.**

---

## Definition of Done

- `mix test test/chat_app/etl/deduplicator_test.exs` — 15/15 green, zero skips
- Test 13 (idempotency: 2N price_history after two runs) passes — this is the spec's primary acceptance criterion for this module
- `mix compile --warnings-as-errors` clean
- No `Repo.insert!` used in `upsert/1` — must use `Repo.insert` and handle `{:error, changeset}` return
- `upsert_all/1` returns `{:ok, [%ClothingItem{id: integer}]}` — ids confirmed non-nil by test 14
