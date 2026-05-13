---
id: SP-04-05
phase: 4
slug: card-rendering-and-smoke
status: complete
created: 2026-05-12
activated_date: 2026-05-12
estimated_days: 1.5
completed_date: 2026-05-13
depends_on:
  - SP-04-04
---

# SP-04-05 — Card Rendering and Smoke Test

**Goal:** Render `pending_cards` as `ProductCard` components below each assistant message, add the "Searching..." status indicator, and verify the full user-visible RAG flow with a manual smoke test.

---

## Scope

### In

- HEEx template updates in `lib/chat_app_web/live/chat_live.ex` — `pending_cards` rendering, `rag_status` indicator
- `lib/chat_app_web/components/product_card.ex` — new functional component
- `priv/static/images/clothing_placeholder.svg` — fallback image asset
- `test/unit/components/product_card_test.exs`
- `test/integration/live/chat_live_card_render_test.exs`
- Manual smoke test (documented in sprint close notes, not in CI)

### Out

- Socket state management (SP-04-04 — complete)
- `ResponseParser`, `StyleAdvisor`, `QueryUnderstander` (earlier sprints)
- Save/unsave item handlers (SP-05)
- `/saved` page (SP-05)

---

## Component Specification

### `ProductCard`

```
<.product_card item={%ClothingItem{}} reason="..." saved={false} />
```

Renders:

- `<img>` with `src={item.image_url}` and `onerror` fallback to `/images/clothing_placeholder.svg`
- `item.name` (title)
- `item.brand` if non-nil
- Size, condition as human label (`good → "Good"`, `like_new → "Like new"`)
- Price: `"$#{price_string}"` — always 2 decimal places
- Source badge: "eBay" / "Depop" / "Poshmark" with source-specific color
- `reason` text in italics below the price
- "View" external link: `href={item.url} target="_blank" rel="noopener noreferrer"`
- Save button: `phx-click="save_item" phx-value-item-id={item.id}` when `saved: false`; "Saved" state when `saved: true` (handlers wired in SP-05; button renders correctly here without being functional)

### Message struct card attachment

After `handle_info(:stream_done)`, `pending_cards` must be moved into the message struct:

```elixir
# message struct gains a :cards field
%{role: :assistant, content: "...", cards: [%{item: %ClothingItem{}, reason: "..."}]}
```

The template iterates `message.cards` (if present) to render `<.product_card>` below the message text. Cards are persisted in the message struct so they survive LiveView re-renders.

### "Searching..." indicator

A UI element driven by `@rag_status`:

```heex
<%= if @rag_status == :searching do %>
  <div data-rag-indicator="searching" class="...">Searching…</div>
<% end %>
```

Hidden when `rag_status` is `:idle` or `:streaming`.

---

## Tests

### Unit — `ProductCard` component

In `test/unit/components/product_card_test.exs`.

---

**U1 — Image renders with onerror fallback attribute**

```elixir
html = render_component(&ProductCard.product_card/1,
  item: %ClothingItem{image_url: "https://example.com/img.jpg", name: "Jeans",
                      size: "M", condition: :good, price: Decimal.new("30.00"),
                      source: :ebay, url: "https://ebay.com/1"},
  reason: "",
  saved: false
)
assert html =~ ~s(src="https://example.com/img.jpg")
assert html =~ "onerror"
assert html =~ "/images/clothing_placeholder.svg"
```

Failure guarded: onerror attribute missing; image broken with no fallback for
hotlink-blocked sources (Depop, Poshmark).

---

**U2 — Nil image_url falls back to placeholder directly in src**

```elixir
html = render_component(&ProductCard.product_card/1,
  item: %ClothingItem{image_url: nil, name: "Jeans", size: "M", condition: :good,
                      price: Decimal.new("30.00"), source: :ebay, url: "https://ebay.com/1"},
  reason: "",
  saved: false
)
assert html =~ ~s(src="/images/clothing_placeholder.svg")
```

Failure guarded: template accessing `item.image_url` directly and crashing on nil
with `ArgumentError`.

---

**U3 — Unsaved state renders "Save" button with correct phx-click and phx-value**

```elixir
html = render_component(&ProductCard.product_card/1, item: item_fixture(), reason: "", saved: false)
assert html =~ ~s(phx-click="save_item")
assert html =~ ~s(phx-value-item-id="#{item_fixture().id}")
assert html =~ "Save"
refute html =~ "Saved"
```

Failure guarded: save button missing phx bindings; "Saved" shown when item is not saved.

---

**U4 — Saved state renders "Saved" text without save phx-click**

```elixir
html = render_component(&ProductCard.product_card/1, item: item_fixture(), reason: "", saved: true)
assert html =~ "Saved"
refute html =~ ~s(phx-click="save_item")
```

Failure guarded: saved/unsaved states not distinguished; save event fireable on
already-saved items, creating duplicate DB rows.

---

**U5 — "View" link has correct href, target, and rel**

```elixir
item = %ClothingItem{item_fixture() | url: "https://ebay.com/item/99"}
html = render_component(&ProductCard.product_card/1, item: item, reason: "", saved: false)
assert html =~ ~s(href="https://ebay.com/item/99")
assert html =~ ~s(target="_blank")
assert html =~ ~s(rel="noopener noreferrer")
```

Failure guarded: missing `rel` attribute exposing window.opener to third-party pages
(security); wrong URL.

---

**U6 — Reason text is rendered**

```elixir
html = render_component(&ProductCard.product_card/1,
  item: item_fixture(), reason: "Great for casual days", saved: false)
assert html =~ "Great for casual days"
```

Failure guarded: reason not passed through to the component or not rendered.

---

**U7 — Condition displayed as human label, not raw atom string**

```elixir
item = %ClothingItem{item_fixture() | condition: :like_new}
html = render_component(&ProductCard.product_card/1, item: item, reason: "", saved: false)
assert html =~ "Like new"
refute html =~ "like_new"
```

Failure guarded: `Atom.to_string(:like_new)` rendered directly instead of a human
label map; user-facing UI showing raw atom syntax.

---

### Integration — ChatLive card rendering

In `test/integration/live/chat_live_card_render_test.exs`.

---

**I1 — Cards rendered below assistant message after stream_done**

```elixir
item = insert(:clothing_item)
msg_with_cards = %{
  role: :assistant,
  content: "Here are some options.",
  cards: [%{item: item, reason: "Good fit"}]
}
socket = assign(socket, messages: [msg_with_cards])
html = render(view)
assert html =~ item.name
assert html =~ "Good fit"
assert html =~ ~s(data-product-card)
```

Failure guarded: cards field ignored in template; product_card component not
rendered for assistant messages.

---

**I2 — Message without cards renders no product card elements**

```elixir
msg_no_cards = %{role: :assistant, content: "Hello there.", cards: []}
socket = assign(socket, messages: [msg_no_cards])
html = render(view)
refute html =~ ~s(data-product-card)
```

Failure guarded: cards rendering for messages that have none; empty list causing
a crash in the template.

---

**I3 — "Searching..." indicator visible when rag_status is :searching**

```elixir
socket = assign(socket, rag_status: :searching)
html = render(view)
assert html =~ ~s(data-rag-indicator="searching")
```

Failure guarded: indicator never shown; user sees no feedback during the
300–700ms HybridEngine latency window.

---

**I4 — "Searching..." indicator not rendered when rag_status is :idle**

```elixir
socket = assign(socket, rag_status: :idle)
html = render(view)
refute html =~ ~s(data-rag-indicator="searching")
```

Failure guarded: indicator permanently visible after RAG flow completes.

---

**I5 — Cards survive LiveView re-render (stored in message struct, not pending_cards)**

```elixir
# After stream_done, pending_cards is [] but cards are in message struct
item = insert(:clothing_item)
msg = %{role: :assistant, content: "Here.", cards: [%{item: item, reason: "Nice"}]}
socket_after_done = assign(socket,
  messages: [msg],
  pending_cards: [],           # cleared by stream_done
  rag_status: :idle
)
html = render(view, socket_after_done)
assert html =~ item.name      # still visible from message struct, not pending_cards
```

Failure guarded: cards rendered from `pending_cards` only — disappearing after
stream completion because that assign is cleared.

---

## Implementation Tasks

- [x] Write all tests (U1–U7, I1–I5) — all failing
- [x] Create `lib/chat_app_web/components/product_card.ex` with `product_card/1` function component
  - [x] Handle `image_url: nil` — render `src="/images/clothing_placeholder.svg"` directly
  - [x] All non-nil images get `onerror="this.onerror=null; this.src='/images/clothing_placeholder.svg'"`
  - [x] Condition label map: `:good → "Good"`, `:like_new → "Like new"`, `:fair → "Fair"`, `:poor → "Poor"`, `:excellent → "Excellent"` (add remaining atoms as needed)
  - [x] Source badge: `:ebay → "eBay"`, `:depop → "Depop"`, `:poshmark → "Poshmark"`
  - [x] "View" link with `target="_blank" rel="noopener noreferrer"`
  - [x] Save button: `phx-click="save_item"` / `phx-value-item-id` when `saved: false`; static "Saved" when `saved: true` (handlers in SP-05)
  - [x] `data-product-card` attribute on root element for test selectors
- [x] Add `clothing_placeholder.svg` to `priv/static/images/`
- [x] Update message struct to include `cards: []` field (default empty list)
- [x] Update `handle_info(:stream_done)` in ChatLive to move `pending_cards` into the last assistant message struct
- [x] Update ChatLive HEEx template:
  - [x] Render `<.product_card>` for each card in `message.cards` below message text
  - [x] Add `data-rag-indicator="searching"` element, visible only when `@rag_status == :searching`
- [x] Run `mix test test/unit/components/product_card_test.exs test/integration/live/chat_live_card_render_test.exs` — all green
- [x] Run `mix test` full suite — zero regressions
- [ ] **Manual smoke test** (required for sprint close, not CI):
  - [ ] Start app with seeded DB
  - [ ] Send: "vintage denim jacket under $60"
  - [ ] Verify "Searching…" indicator appears within 500ms of send
  - [ ] Verify at least one product card renders below the assistant message within 8 seconds
  - [ ] Verify card shows item name, price, source badge, and reason text
  - [ ] Log result with timestamp in sprint close notes

---

## Definition of Done

- [ ] All 12 unit and integration tests pass
- [ ] E2E tests pass on seeded DB (`mix test --include e2e`)
- [ ] `mix test` full suite green — zero regressions
- [ ] Manual smoke test logged with timestamp: "vintage denim jacket under $60" → ≥1 card renders within 8 seconds
- [ ] `clothing_placeholder.svg` committed to `priv/static/images/`
- [ ] No `save_item` / `unsave_item` event handlers wired in this sprint — save button renders but clicking it is a no-op or raises a handled no-match (SP-05 owns those handlers)
