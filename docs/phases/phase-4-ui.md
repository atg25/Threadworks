---
status: draft
last_updated: 2026-05-06
phase: 4
sub_phase: 4
slug: ui
complexity: L
---

# Phase 4 — UI: Cards, Saved Items, Preferences

**Goal:** Render recommendation cards inline in chat and let users save, organize, and price-track items.

---

## Deliverables

### `lib/chat_app_web/components/product_card.ex`

Functional component. Attributes: `item`, `saved` (bool), `reason`.

Renders:
- `<img src={item.image_url} onerror="this.onerror=null; this.src='/images/clothing_placeholder.svg'" alt={item.title}>`
- Title, brand, size, `condition_normalized` displayed as human label (good → "Good")
- Price formatted as `"$#{Decimal.to_string(item.price, :normal)}"` — always 2 decimal places
- Source badge: "eBay" / "Depop" / "Poshmark" styled per source color
- Reason text (from LLM, e.g., "Great fit for your stated style")
- Save/Saved toggle: `phx-click="save_item"` when unsaved, `phx-click="unsave_item"` when saved; `phx-value-item-id={item.id}`
- "View" external link: `href={item.url} target="_blank" rel="noopener noreferrer"`

### `priv/static/images/clothing_placeholder.svg`

Simple grey clothing-hanger silhouette SVG. Referenced by `onerror` fallback.

### `lib/chat_app_web/live/chat_live.ex` updates

Card rendering:
- Socket assign `:pending_cards` (list of `%{item: %ClothingItem{}, reason: String.t()}`) populated by `ResponseParser` events during streaming
- After stream completion, cards are attached to the assistant message struct for persistent rendering
- Render `<.product_card>` components below the assistant message text in the message list template

Event handlers:
```elixir
handle_event("save_item", %{"item-id" => id}, socket)
  → Clothing.save_item(current_user.id, String.to_integer(id), current_price)
  → update :saved_item_ids assign (MapSet.put)

handle_event("unsave_item", %{"item-id" => id}, socket)
  → Clothing.unsave_item(current_user.id, String.to_integer(id))
  → update :saved_item_ids assign (MapSet.delete)

handle_event("refresh_listings", _, socket)
  → enqueue one ScrapeWorker job per source in :scrape_queries config
  → push flash: "Refreshing listings in the background"
```

Socket assigns to add: `:saved_item_ids` (MapSet, loaded on mount from `Clothing.list_saved_item_ids(user_id)`), `:rag_status` (`:idle | :searching | :streaming`), `:last_scraped_at` (loaded on mount).

### `lib/chat_app/clothing.ex` additions

```elixir
save_item(user_id, item_id, price_at_save)
  → Repo.insert(%SavedItem{...}, on_conflict: :nothing, conflict_target: [:user_id, :item_id])

unsave_item(user_id, item_id)
  → Repo.delete_all(from s in SavedItem, where: s.user_id == ^user_id and s.item_id == ^item_id)

list_saved_items(user_id)
  → SavedItem |> where(user_id: ^user_id) |> preload(:item) |> order_by(desc: :inserted_at) |> Repo.all()

list_saved_item_ids(user_id)
  → SavedItem |> where(user_id: ^user_id) |> select([s], s.item_id) |> Repo.all() |> MapSet.new()

get_price_delta(saved_item)
  → fetch 2 most recent price_history rows for item_id
  → if < 2 rows: :no_history
  → else: %{saved_price: Decimal, current_price: Decimal, delta_pct: float}
     delta_pct = (current - saved) / saved * 100
```

### `lib/chat_app_web/live/saved_live.ex`

Route: `/saved` (authenticated, inside existing `live_session` block).

Renders:
- 2-column card grid (`sm:grid-cols-1 md:grid-cols-2`)
- Each card: `<.product_card>` plus price delta badge
  - 2+ price_history entries: "↓15% · Now $38" (green if cheaper, red if pricier) or "↑8% · Now $49"
  - 1 entry: "No price history"
  - `item_id: nil` (listing removed): show greyed card with "Listing Removed" overlay
- Filter bar: source dropdown (All / eBay / Depop / Poshmark), sort by (Price ↑, Price ↓, Recently saved)

### `lib/chat_app_web/router.ex` update

Inside the authenticated `live_session` block:
```elixir
live "/saved", SavedLive
```

### `UserLive.Settings` preferences section

Add below existing email/password settings:

| Field | Control | Storage |
|---|---|---|
| Sizes | Multi-select checkboxes: XS, S, M, L, XL, XXL, plus numeric sizes 0–18 | JSON array in `user_preferences.sizes` |
| Brands | Comma-separated text input | JSON array in `user_preferences.brands` |
| Budget | Two number inputs (min / max) with $ prefix | `budget_min`, `budget_max` as Decimal |
| Style keywords | Comma-separated text input | JSON array in `user_preferences.style_keywords` |

Save on submit via `ChatApp.Accounts.save_preferences(user_id, attrs)` → upsert `user_preferences`.

### Chat sidebar additions

- "Refresh listings" button with spinner on click
- "Last scraped: {time_ago}" label (uses `last_scraped_at` from socket assigns; hidden if nil)

---

## Acceptance Criteria

All LiveView tests use `Phoenix.LiveViewTest`.

- **ProductCard image fallback (unit):** `render_component(ProductCard, item: %ClothingItem{image_url: nil}, saved: false, reason: "")` — rendered HTML `<img src>` equals `/images/clothing_placeholder.svg`
- **ProductCard onerror attribute (unit):** Rendered HTML contains `onerror=` attribute on `<img>` for any `image_url`
- **ProductCard save state (unit):** With `saved: false` → button text contains "Save"; with `saved: true` → button text contains "Saved"
- **Save idempotency (LiveView test):** Click "save_item" with `item_id: 5` twice rapidly → `Repo.aggregate(from(s in SavedItem, where: s.item_id == 5), :count)` = 1; no unique constraint error raised (uses `on_conflict: :nothing`)
- **Unsave (LiveView test):** Save then unsave item → `Repo.get_by(SavedItem, item_id: 5, user_id: user.id)` is nil
- **Saved page auth (LiveView test):** `get(conn, "/saved")` when not logged in → redirected to `/users/log-in`
- **Price delta present (LiveView test):** Insert 2 `price_history` rows for item (prices: 45.00, 38.00); `SavedItem` for same item; mount `SavedLive` → rendered HTML contains "↓15%" or "Now $38"
- **Price delta absent (LiveView test):** Insert 1 `price_history` row → rendered HTML contains "No price history"
- **Listing removed (LiveView test):** `SavedItem` with `item_id: nil` → rendered HTML contains "Listing Removed"
- **Refresh listings (LiveView test):** Click "Refresh listings" → `Oban.Job |> where([j], j.worker == "ChatApp.ETL.Workers.ScrapeWorker") |> Repo.aggregate(:count)` increases by the count of configured sources (e.g., 3 for ebay/depop/poshmark)
- **Preferences persist (LiveView test):** Submit preferences form with `sizes: ["S", "M"]` → `UserPreferences |> Repo.get_by(user_id: user.id)` has `sizes` JSON equal to `["S","M"]`; re-mount settings page → S and M checkboxes are checked

---

## Dependencies

- Phase 3 complete (card data emitted by ResponseParser)
- Phase 0 complete (saved_items, user_preferences schema; placeholder SVG committed)
- Existing user auth (`current_user` in socket assigns, authenticated live_session)

Note: `SavedLive` and the preferences form can be scaffolded against Phase 0 schema with factory-seeded data before Phase 3 is complete. Only card rendering in `ChatLive` requires Phase 3.

---

## Complexity: L

Broadest surface area of any phase: new LiveView page, new functional component, 6 new event handlers, price delta arithmetic, preferences form, router change, and sidebar additions — all while preserving existing ChatLive behavior.

---

## Risks

- **External image hotlinking:** eBay images generally load. Depop and Poshmark may block hotlinking from non-browser origins. The `onerror` fallback handles this client-side without server-side proxying. If the placeholder itself is 404, the `<img>` will be broken — ensure `/images/clothing_placeholder.svg` is committed to `priv/static/images/`.
- **Price delta edge cases:** `get_price_delta/1` must handle `Decimal.div/2` when `saved_price` is 0 (free item) — return `:no_history` or a special `:free` case rather than divide-by-zero.
- **`item_id: nil` in saved_items:** The `ON DELETE SET NULL` FK means `preload(:item)` on a saved_item with `item_id: nil` returns `nil` for the `:item` field. `SavedLive` template must guard against `nil` item with a "Listing Removed" branch before accessing any item fields.
- **Mobile layout:** Use `sm:grid-cols-1 md:grid-cols-2` for the saved items grid. Test the product card at 375px viewport — ensure price, badge, and buttons don't overflow.
- **Oban in test environment:** Use `Oban.Testing.with_testing_mode(:inline, fn -> ... end)` or assert on job insertion counts rather than waiting for job completion in tests.
