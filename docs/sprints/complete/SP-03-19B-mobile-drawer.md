---
id: SP-3-19B
phase: 3
status: complete
created: Apr-28-2026
activated: Apr-29-2026
completed: Apr-29-2026
---

# Goal
Ensure the sidebar is accessible on mobile devices via a slide-out drawer.

## Existing Baseline

This sprint starts from a shipped desktop-collapsible sidebar and a page shell that keeps the footer below the initial viewport.

# Scope
- **In:** Mobile off-canvas drawer logic, backdrop overlay.
- **Out:** Reworking the shipped desktop default-collapsed behavior or undoing the footer/page-shell structure.

## Do Not Revert Existing Ad-hoc Work

- Mobile drawer logic must be additive on top of the current desktop sidebar behavior.
- Keep the desktop default-collapsed state intact at desktop breakpoints.
- Do not regress the dedicated page-shell scrolling or pull the footer back into the initial viewport while adding mobile overlays.
- Affected files: `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/live/sidebar_component.ex`, `chat_app/lib/chat_app_web/components/layouts.ex`, `chat_app/lib/chat_app_web/components/layouts/root.html.heex`.

# Tests
## E2E Happy Path
`test "sidebar behaves as off-canvas drawer on mobile viewports"`
- **Inputs:** Viewport `390px`, click toggle.
- **Expected:** Sidebar opens as a `z-30` absolute-positioned element; main chat layout does not resize.
- **Guards Against:** Desktop grid logic breaking mobile constraints.

## E2E Negative 1
`test "clicking the mobile backdrop overlay closes the sidebar"`
- **Inputs:** Open drawer on mobile, click backdrop.
- **Expected:** Sidebar closes, backdrop disappears.
- **Guards Against:** Trapping mobile users in a state.

# Implementation Tasks
- [x] Write E2E tests for off-canvas behavior and backdrop dismissal.
- [x] Implement a backdrop overlay `div` that only renders when `sidebar_open?` is true on mobile.
- [x] Add responsive CSS classes (`md:relative`, `absolute`) to the sidebar container based on breakpoints without changing the shipped desktop layout semantics.

# Definition of Done
- [x] All tests pass.
- [x] Manual check: Resize browser from `390px` to `1024px` while the sidebar is open; ensure it seamlessly transitions from absolute drawer to flex column.
