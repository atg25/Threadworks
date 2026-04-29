---
id: SP-3-20
phase: 3
status: complete
created: Apr-28-2026
activated: Apr-29-2026
completed: Apr-29-2026
---

# Goal
Wire up the robust design system themes to the UI, replacing the basic light/dark toggles.

## Existing Baseline

Most of this sprint is already live ad-hoc:

- The header already renders the four named theme options `editorial`, `swiss`, `mid-century`, and `techno-brutalist`.
- Theme changes already flow through `<html data-theme>` and persist via `localStorage`.
- The remaining work is hardening, active-state polish, and regression protection.

# Scope
- **In:** Hardening the shipped 4-option theme toggle, persistence across LiveView patches, active-state polish, and any remaining JS/layout cleanup.
- **Already done:** 4-option named theme selector, `localStorage` persistence, `data-theme` mapping on `<html>`.
- **Out:** Creating new themes or reverting to the earlier system/light/dark controls.

## Do Not Revert Existing Ad-hoc Work

- Do not replace the shipped named-theme selector with a light/dark/system triad.
- Do not remove the `data-theme` contract on `<html>` or the `localStorage` bridge that preserves theme choice.
- Do not let LiveView patches stomp the JS-managed theme attributes while refactoring related code.
- Affected files: `chat_app/assets/js/app.js`, `chat_app/lib/chat_app_web/components/layouts/root.html.heex`, `chat_app/lib/chat_app_web/live/chat_live.ex`.

# Tests
## E2E Happy Path
`test "visual theme updates immediately and persists across reloads"`
- **Inputs:** Click "Swiss", reload page.
- **Expected:** Computed background color matches the "Swiss" theme variables on load.
- **Guards Against:** State not propagating or failing to save.

## E2E Negative 1
`test "LiveView patches do not overwrite JS-managed theme attributes"`
- **Inputs:** Apply theme, trigger LiveView DOM patch via sending a message.
- **Expected:** Computed theme styles remain active and the DOM does not revert to default.
- **Guards Against:** Server-rendered DOM diffing wiping out JS-driven state.

## Unit
`test "theme JS hook sets localStorage and DOM attributes correctly"`
- **Inputs:** Dispatch theme change event.
- **Expected:** `localStorage.getItem('theme')` updates, `document.documentElement.dataset.theme` updates.
- **Guards Against:** Broken integration boundary between LiveView and JS.

# Implementation Tasks
- [x] Write E2E and Unit regression tests around the shipped theme selector.
- [x] Polish active/selected state styling for the current 4-button theme control.
- [x] Verify the existing JS hook continues to manage `data-theme` and `localStorage` correctly under LiveView patches.
- [x] Keep `root.html.heex` configured so `<html>` theme attributes remain JS-controlled.

# Definition of Done
- [x] All tests pass.
- [x] Manual check: Switch themes rapidly; verify no console errors occur and buttons display active states correctly.
