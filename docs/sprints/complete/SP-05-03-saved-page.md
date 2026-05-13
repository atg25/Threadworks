---
id: SP-05-03
phase: 5
status: complete
created: 2026-05-12
activated_date: 2026-05-13
completed_date: 2026-05-13
---

# SP-05-03 — Saved items page (`/saved`)

Goal
----
Add an authenticated LiveView at `/saved` that lists a user's saved items in a responsive grid, shows price deltas, supports filtering by source and sorting, and correctly handles removed listings.

Scope
-----
- In: `lib/chat_app_web/live/saved_live.ex`, LiveView template, router entry inside authenticated `live_session`, tests for auth, filters, sort, price delta rendering, and removed-listing branch.
- Out: backend persistence (SP-05-02), ChatLive streaming (SP-05-04).

Tests
-----
Unit

- Name: format_price_delta_badge_renders_decrease
  - Inputs: `%{saved_price: Decimal.new("45.00"), current_price: Decimal.new("38.00")}`
  - Expected: Badge text contains "↓15%" and badge has class indicating green/cheaper styling.
  - Guards against: wrong percent calculation or color inversion.

- Name: format_price_delta_badge_renders_no_history
  - Inputs: `:no_history`
  - Expected: Badge text equals "No price history".
  - Guards against: crash when history absent.

- Name: saved_card_renders_listing_removed_when_item_nil
  - Inputs: `SavedItem` with `item: nil`
  - Expected: Template shows a visible "Listing Removed" overlay and does not dereference `nil`.
  - Guards against: template crash on nil preload.

Integration

- Name: saved_live_mount_loads_saved_items_and_defaults
  - Inputs: authenticated user with saved items.
  - Expected: on mount assigns contain `:saved_items` list, `:filter_source` defaulting to "All", and `:sort_by` defaulting to "Recently saved".
  - Guards against: missing data on mount or wrong defaults.

- Name: saved_live_filters_by_source
  - Inputs: saved items from eBay and Depop; simulate selecting filter "Depop".
  - Expected: only Depop cards are rendered.
  - Guards against: server-side filters miswired or client-only filters that don't hold on refresh.

E2E

- Name: saved_live_happy_path_renders_saved_cards
  - Inputs: authenticated user with a saved item and two price_history rows (45.00 then 38.00).
  - Expected: page contains the product card, shows "↓15%" and "Now $38" text, and view link opens externally.
  - Guards against: missing delta or broken card rendering.

- Name: saved_live_no_history_shows_message (edge)
  - Inputs: saved item with single price_history row.
  - Expected: page contains "No price history" for that card.
  - Guards against: incorrect delta shown.

- Name: saved_live_removed_listing_shows_overlay (edge)
  - Inputs: saved item with `item_id: nil` (DB left NULL after item deletion).
  - Expected: card shows "Listing Removed" and does not attempt to render item fields.
  - Guards against: crash or NPE in template.

Implementation tasks
--------------------

- [x] Add route `live "/saved", SavedLive` in authenticated `live_session` in `lib/chat_app_web/router.ex`.
- [x] Implement `SavedLive` mount to call `ChatApp.Clothing.list_saved_items(user.id)` and load filter/sort defaults.
- [x] Build saved page template with responsive grid (`sm:grid-cols-1 md:grid-cols-2`), render `<.product_card>` per saved item, show price delta badge, and show "Listing Removed" overlay for `nil` items.
- [x] Implement server-side filter and sort handling and expose UI controls.
- [x] Add LiveView tests for auth redirect, mount, filter, sort, delta, and removed-listing cases.

Definition of done
------------------

- [ ] Route requires login and redirects unauthenticated requests to `/users/log-in`.
- [ ] All unit/integration/E2E tests pass in CI.
- [ ] Manual checks: login, visit `/saved`, apply filter and sort, verify removed-listing overlay and delta badges.
- [x] Accessibility: delta badge includes ARIA label for screen readers.
