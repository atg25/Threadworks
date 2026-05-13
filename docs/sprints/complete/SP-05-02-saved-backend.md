---
id: SP-05-02
phase: 5
status: complete
created: 2026-05-12
activated_date: 2026-05-13
completed_date: 2026-05-13
---

# SP-05-02 — Saved item backend

## Goal

Implement `save_item/3`, `unsave_item/2`, `list_saved_items/1`, `list_saved_item_ids/1`, and `get_price_delta/1` with robust handling of edge cases (zero price, insufficient history) and concurrency idempotency.

## Scope

- In: `lib/chat_app/clothing.ex` functions, DB tests for saved items and price_history, concurrency tests.
- Out: LiveView handlers and UI (covered in SP-05-04), scraping or ETL jobs.

## Tests

Unit

- Name: save_item_inserts_idempotently
  - Inputs: call `save_item(user_id, item_id, Decimal.new("39.00"))` twice in same test.
  - Expected: `Repo.aggregate(from(s in SavedItem, where: s.user_id==^user_id and s.item_id==^item_id), :count)` returns `1` and no exception raised.
  - Guards against: duplicate inserts or unhandled unique constraint errors.

- Name: unsave_item_deletes_row_or_noop
  - Inputs: existing `SavedItem` row; call `unsave_item(user_id, item_id)`.
  - Expected: `Repo.get_by(SavedItem, user_id: user_id, item_id: item_id)` is `nil` after call.
  - Guards against: stale saved state remaining.

- Name: list_saved_item_ids_returns_mapset_of_integers
  - Inputs: saved items for user with ids [5,7].
  - Expected: `MapSet.new([5,7])` returned (exact type);
  - Guards against: wrong return type or duplicates.

- Name: get_price_delta_returns_no_history_for_one_row
  - Inputs: one `price_history` row exists for the item.
  - Expected: Function returns `:no_history` (or agreed contract) and does not raise.
  - Guards against: bogus delta for insufficient history.

- Name: get_price_delta_uses_two_most_recent_rows
  - Inputs: history rows at times T1=50.00, T2=45.00, T3=40.00 (T3 newest).
  - Expected: uses T2 (45.00) and T3 (40.00) to compute delta = ((40-45)/45)\*100.
  - Guards against: selecting incorrect rows for delta.

- Name: get_price_delta_handles_zero_saved_price_gracefully
  - Inputs: saved_price = Decimal.new("0.00"), current_price = Decimal.new("0.00")
  - Expected: returns `:no_history` or `:free` per contract; no divide-by-zero exceptions.
  - Guards against: Decimal division by zero crash.

Integration

- Name: save_item_concurrent_calls_produce_single_row
  - Inputs: spawn two tasks that call `save_item(user_id, item_id, price)` concurrently.
  - Expected: final DB count for saved item is `1` and no unhandled constraint errors.
  - Guards against: race conditions producing duplicates.

- Name: save_item_persists_price_with_two_decimal_precision
  - Inputs: `price_at_save = Decimal.new("19.9")`
  - Expected: persisted column equals `Decimal.new("19.90")` or canonical two-decimal representation.
  - Guards against: precision loss.

E2E

- Name: save_item_backend_happy_path
  - Inputs: call `ChatApp.Clothing.save_item(user.id, item.id, price)` once from test harness.
  - Expected: saved item exists in DB with `user_id`, `item_id`, and `price_at_save` persisted.
  - Guards against: failure to persist saves.

- Name: unsave_item_nonexistent_item_edge
  - Inputs: call `unsave_item` for a user/item that is not saved.
  - Expected: function returns `:ok` or `{:ok, :deleted}` and no error raised; DB unchanged.
  - Guards against: crash when deleting nonexistent rows.

- Name: save_item_duplicate_rapid_edge
  - Inputs: call `save_item` twice rapidly (serial or concurrent) from test.
  - Expected: only one saved row exists and no unique constraint error surfaced.
  - Guards against: race leading to duplicate rows or user-facing 500 error.

## Implementation tasks

- [ ] Implement `save_item/3` with `Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :item_id])`.
- [ ] Implement `unsave_item/2` using `Repo.delete_all` filter.
- [ ] Implement `list_saved_items/1` with `preload(:item)` and ordering.
- [ ] Implement `list_saved_item_ids/1` returning `MapSet` of integers.
- [ ] Implement `get_price_delta/1` selecting two most recent `price_history` rows and handling zero saved price safely.
- [ ] Add ExUnit tests for units and concurrency and integration tests.

## Definition of done

- [ ] All unit and integration tests pass in CI under realistic DB concurrency simulation.
- [ ] E2E tests for save/unsave pass.
- [ ] `get_price_delta` contract is documented in code and PR description (chooses `:no_history` for insufficient or zero-handling behavior explicitly stated).
- [ ] Migration or schema assumptions documented in PR.
