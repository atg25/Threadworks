---
id: SP-3-19A
phase: 3
status: complete
created: Apr-28-2026
activated: Apr-29-2026
completed: Apr-29-2026
---

# Goal
Clean up header controls and implement a collapsible sidebar for desktop viewports.

## Existing Baseline

The current app already shipped most of this sprint ad-hoc. Treat the following as baseline, not open scope:

- Desktop sidebar collapse exists and currently defaults to collapsed on first load.
- Header text pills are already removed.
- The current header layout is a left hamburger toggle, a square `hero-pencil-square` new-chat button beside the wordmark, and a right settings gear.
- The top model strip and API cost tracker are already gone.
- The footer now depends on page-shell scrolling and should remain below the initial viewport.

# Scope
- **In:** Desktop collapse hardening, accessibility, transition polish, and regression coverage for the shipped layout.
- **Already done:** Desktop collapsible sidebar, icon-led header controls, removal of the top model strip, removal of the API cost tracker.
- **Out:** Mobile off-canvas drawer.

## Do Not Revert Existing Ad-hoc Work

- Do not reintroduce the old `+ New` / `Settings` text pills or the prior monogram-style new-chat control.
- Do not reopen the sidebar by default on desktop.
- Do not restore the top `gpt-4o-mini` badge or any `data-usage-cost` UI above the transcript.
- Do not reintroduce global `overflow:hidden` layout locking that would pull the footer back into the initial viewport.
- Affected files: `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/live/sidebar_component.ex`, `chat_app/lib/chat_app_web/components/layouts.ex`, `chat_app/lib/chat_app_web/components/layouts/root.html.heex`.

# Tests
## E2E Happy Path
`test "sidebar collapses and expands via header toggle on desktop"`
- **Inputs:** Viewport `1024px`, click `hero-bars-3` toggle.
- **Expected:** Sidebar container width transitions to `0px` and chat composer expands to fill space.
- **Guards Against:** Broken layout transitions or unclickable toggles.

## E2E Negative 1
`test "API cost tracker is completely removed from the DOM"`
- **Inputs:** Visit `/`.
- **Expected:** Element `[data-usage-cost]` does not exist.
- **Guards Against:** Lingering dead code.

## E2E Negative 2
`test "header icon buttons are keyboard accessible"`
- **Inputs:** Tab through header.
- **Expected:** "+ New" and "Settings" icons receive visual focus rings and can be triggered via `Enter`.
- **Guards Against:** Accessibility regressions.

# Implementation Tasks
- [x] Write E2E regression tests for default-collapsed desktop behavior, absence of the old model/API chrome, and header accessibility.
- [x] Harden existing width/transition behavior without changing the shipped default state.
- [x] Polish focus, spacing, and keyboard interactions around the current icon-only header.
- [x] Verify the below-fold footer still behaves correctly after any desktop layout refactor.

# Definition of Done
- [x] All tests pass.
- [x] Manual check: Toggling the sidebar does not cause vertical layout jumping in the chat transcript.
