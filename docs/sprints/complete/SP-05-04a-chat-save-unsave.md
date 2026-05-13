---
id: SP-05-04a
phase: 5
status: complete
activated_date: 2026-05-13
completed_date: 2026-05-13
created: 2026-05-12
---

# SP-05-04a — ChatLive save/unsave events and assigns hydration

Goal
----
Wire `ChatLive` mount to hydrate `:saved_item_ids`, `:rag_status`, and `:last_scraped_at`; implement `save_item` and `unsave_item` event handlers to persist and update socket assigns and DOM state.

Scope
-----
- In: `lib/chat_app_web/live/chat_live.ex` mount changes, `handle_event/3` for `save_item` and `unsave_item`, LiveView tests for assign updates and persisted rows.
- Out: streaming pending-card attach (SP-05-04b), saved page UI (SP-05-03).

Tests
-----
Unit

- Name: chat_live_mount_initializes_saved_item_ids_and_status
  - Inputs: mount `ChatLive` with an authenticated user who has saved items but no `last_scraped_at`.
  - Expected: `socket.assigns.saved_item_ids` is a `MapSet` containing saved ids; `:rag_status` equals `:idle`; `:last_scraped_at` equals nil or DB value.
  - Guards against: missing initial assigns.

- Name: chat_live_sets_rag_status_assigns
  - Inputs: mount without any scraping activity.
  - Expected: `:rag_status` assigned to `:idle`.
  - Guards against: undefined status leading to runtime errors.

Integration

- Name: chat_live_handle_save_item_updates_assigns
  - Inputs: `handle_event("save_item", %{"item-id" => "5"}, socket)` where user is authenticated.
  - Expected: saved id added to `socket.assigns.saved_item_ids` and `SavedItem` row persisted.
  - Guards against: assign not updated or DB not persisted.

- Name: chat_live_handle_unsave_item_updates_assigns
  - Inputs: `handle_event("unsave_item", %{"item-id" => "5"}, socket)` with item saved before call.
  - Expected: saved id removed from assigns and DB row deleted.
  - Guards against: unsave ignored or stale assign.

E2E

- Name: chat_live_save_item_happy_path
  - Inputs: mount ChatLive with a rendered product card and click `save_item` event on the card control in the test harness.
  - Expected: DOM updates to show "Saved" and `SavedItem` exists in DB for user/item.
  - Guards against: event not wired to persistence.

- Name: chat_live_unsave_item_happy_path (edge)
  - Inputs: saved item present; trigger `unsave_item` click.
  - Expected: DOM updates back to "Save" and DB row removed.
  - Guards against: DOM not reflecting DB change.

- Name: chat_live_save_idempotency_under_race_conditions (edge)
  - Inputs: simulate concurrent `save_item` events (two rapid clicks or concurrent calls in test).
  - Expected: one persisted `SavedItem` row and no exception surfaced to client.
  - Guards against: duplicate rows or 500 errors.

Implementation tasks
--------------------

- [x] Load `:saved_item_ids`, `:rag_status`, and `:last_scraped_at` in `ChatLive.mount/3` from `ChatApp.Clothing.list_saved_item_ids/1` and relevant sources.
- [x] Add `handle_event("save_item", params, socket)` to call `ChatApp.Clothing.save_item/3` and update `socket.assigns.saved_item_ids` using `MapSet.put`.
- [x] Add `handle_event("unsave_item", params, socket)` to call `ChatApp.Clothing.unsave_item/2` and update assigns using `MapSet.delete`.
- [x] Add tests that assert assigns and DB rows after events.
- [x] Ensure flash/errors are surfaced gracefully on DB error.

Definition of done
------------------

- [x] All unit and integration tests pass.
- [x] E2E flows (save/unsave) pass in test harness.
- [x] Manual check: clicking save toggles the button text and persisted state.
- [x] No unhandled 500s occur when save is called rapidly.
