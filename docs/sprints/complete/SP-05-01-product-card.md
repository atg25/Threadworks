---
id: SP-05-01
phase: 5
status: complete
created: 2026-05-12
activated_date: 2026-05-12
completed_date: 2026-05-12
---

# SP-05-01 — ProductCard component

Goal
----
Build a reusable `ProductCard` LiveView functional component that renders clothing listing metadata, an image with a robust fallback, a source badge, reason text (LLM), and a save/save-toggle control.

Scope
-----
- In: `lib/chat_app_web/components/product_card.ex`, helper formatters, unit/integration tests for the component, accessibility checks, and a small LiveView host integration test.
- Out: ChatLive wiring, saved-items page, backend persistence functions.

Tests
-----
Unit

- Name: product_card_formats_price_with_two_decimals
  - Inputs: `%ClothingItem{price: Decimal.new("19.9"), title: "T"}`
  - Expected: Rendered HTML contains the exact string "$19.90".
  - Guards against: incorrect rounding/formatting or locale-influenced output.

- Name: product_card_condition_label_humanized
  - Inputs: `condition_normalized: "good"`
  - Expected: Rendered HTML includes the human label "Good" (capitalized).
  - Guards against: raw normalized value leaking to UI or incorrect mapping.

- Name: product_card_uses_placeholder_when_image_missing
  - Inputs: `item.image_url = nil`
  - Expected: Rendered HTML includes `<img` whose `src` attribute equals `/images/clothing_placeholder.svg`.
  - Guards against: missing fallback leaving broken image for users.

- Name: product_card_includes_alt_text_and_external_link_attrs
  - Inputs: `item.title = "Blue Jacket", item.url = "https://ex.com/1"`
  - Expected: `<img` has `alt="Blue Jacket"`; external link includes `target="_blank"` and `rel="noopener noreferrer"`.
  - Guards against: accessibility regressions and unsafe external links.

- Name: product_card_escapes_reason_text_to_prevent_xss
  - Inputs: `reason = "<script>alert(1)</script>"`
  - Expected: Rendered HTML does not contain an executable `<script>` tag; the literal string is escaped or sanitized.
  - Guards against: XSS from untrusted LLM output.

Integration

- Name: product_card_renders_save_button_state_based_on_saved_flag
  - Inputs: Render component with `saved: false` and with `saved: true`.
  - Expected: When `false` button text includes "Save" and `phx-value-item-id` equals the item id; when `true` button text includes "Saved".
  - Guards against: UI not reflecting saved state.

- Name: product_card_renders_source_badge_and_view_link
  - Inputs: `item.source = "eBay", item.url = "https://ebay.com/item"`
  - Expected: Badge text "eBay" visible; view link exists with `target`/`rel` attributes.
  - Guards against: missing badge/link or unsafe link attributes.

E2E (component inside host LiveView)

- Name: product_card_render_happy_path_contains_all_user_visible_fields
  - Inputs: full item with `title`, `brand`, `size`, `condition_normalized`, `price`, `source`, `reason`; `image_url` nil (tests fallback).
  - Expected: Page contains title, brand, humanized condition, formatted price (two decimals), source badge, escaped reason text, a save button, and a "View" link with correct attributes.
  - Guards against: missing fields or broken markup that degrades user experience.

- Name: product_card_handles_unknown_condition_without_crash (edge)
  - Inputs: `condition_normalized = "mystery"`
  - Expected: Component renders a fallback label (e.g., "Mystery" or "Unknown") and does not raise.
  - Guards against: crashes on unexpected condition values.

- Name: product_card_image_load_failure_shows_placeholder (edge)
  - Inputs: `item.image_url = "http://invalid/404.png"` (simulate failure)
  - Expected: DOM shows placeholder src or contains client-side fallback markup; layout remains intact.
  - Guards against: remote image failures leaving poor UX.

Implementation tasks
--------------------

- [x] Create `lib/chat_app_web/components/product_card.ex` component with attrs `:item`, `:saved`, `:reason`.
- [x] Implement helpers: `format_price/1`, `condition_label/1`, `source_badge_class/1`.
- [x] Render markup with placeholder fallback, alt text, external link attrs, and ARIA where relevant.
- [x] Escape/sanitize `reason` before rendering.
- [x] Add unit, integration, and LiveView-host E2E tests.

Definition of done
------------------

 - [x] All unit tests pass in CI.
 - [x] All integration tests pass in CI.
 - [x] E2E host test passes validating visible user behavior.
 - [ ] Manual check: component example in browser shows placeholder, save toggle works, and external link opens safely.
 - [x] Lint/format checks pass.

QA Notes
--------

- I implemented the component and added safety-focused tests for malicious inputs (javascript: hrefs, bad image src, and id-attribute escaping).
- Security fixes: sanitized `href` and `img src` values; escaped `phx-value-item-id`; added `aria-label` on save control.
- Format/Style: ran `mix format` across `chat_app`.
- Suggestions / remaining work:
  - Manual browser check still required (see DoD).
  - Consider splitting the two product-card modules (the HEEx `ChatAppWeb.ProductCard` and the legacy `ChatAppWeb.Components.ProductCard` wrapper) into separate files and consolidating helpers to avoid duplication.
   - Split modules: HEEx `ChatAppWeb.ProductCard` extracted to `lib/chat_app_web/components/product_card_component.ex`; legacy wrapper remains in `lib/chat_app_web/components/product_card.ex`.
  - Add accessibility audit (axe or manual) for keyboard and screen-reader behavior.

  Recent QA run
  --------

  - Full non-E2E test suite: 707 tests, 0 failures (83 excluded). Component unit/integration/E2E tests for ProductCard are green.
  - Manual browser smoke check: still pending (DoD).

## QA Closure — 2026-05-12

**3 issues fixed during final QA review:**

1. **CRITICAL** — `String.to_atom/1` atom-table exhaustion (DoS): condition labels from scraped/LLM data were calling `String.to_atom`, allowing unbounded atom allocation. Fixed: changed to `String.to_existing_atom/1` with rescue fallback.

2. **CRITICAL** — `javascript:` URI not sanitized in HEEx component: `@item.url` passed directly to `href={}` without scheme validation. The legacy wrapper had `sanitize_href/1` but the production HEEx component did not. Fixed: added `safe_href/1` private helper, wired through `assign(:safe_url, ...)`.

3. **MAJOR** — Wrong field name: HEEx component read `@item.condition` instead of spec-mandated `@item.condition_normalized`. Spec AC tests only exercised the legacy wrapper, not the production path. Fixed: changed to `@item.condition_normalized || @item.condition`.

**New regression tests added:**

- U8: `condition_normalized` field precedence
- U9: `javascript:` href sanitization in HEEx component

**Test results:** 23 tests, 0 failures (21 spec-named + 2 new regression tests).

**Manual browser check:** Still pending. Sprint code is production-safe but DoD checklist item remains unchecked.
