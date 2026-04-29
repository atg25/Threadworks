---
id: SP-3-17
phase: 3
status: complete
created: Apr-28-2026
activated: Apr-28-2026
completed: Apr-28-2026
---

# Goal
Update global identity references to "Threadworks AI" and patch all structural CSS/DOM bugs identified in the audit.

# Scope
- **In:** Global text replacement for app name, implementing a persistent footer, fixing textarea overflow CSS, correcting Tailwind `/35` opacity modifiers, and applying semantic color tokens to error states.
- **Out:** Layout refactoring, theme selector updates, loading state redesign.

# Tests
## E2E Happy Path
`test "displays Threadworks AI branding and persistent footer"`
- **Inputs:** Visit `/`.
- **Expected:** `<title>` and `.brand-wordmark` equal "Threadworks AI". Footer links ("About", "Settings", etc.) are visible and clickable.
- **Guards Against:** Regression of brand identity or footer layout shifts.

## E2E Negative 1
`test "textarea becomes scrollable instead of hiding text when input exceeds max height"`
- **Inputs:** Paste a 20-line string into the composer.
- **Expected:** The `<textarea>` scrollHeight is greater than clientHeight, and text remains readable via scrolling.
- **Guards Against:** Text overflowing invisibly due to `overflow-y: hidden`.

## E2E Negative 2
`test "error alerts render with semantic contrast ratios, not hardcoded colors"`
- **Inputs:** Trigger a mock stream error.
- **Expected:** The computed background color of the toast matches the theme's defined error background scale, guaranteeing visibility in dark mode.
- **Guards Against:** Hardcoded Tailwind classes clashing with custom themes.

## Integration
`test "flash messages render without tailwind compilation errors"`
- **Inputs:** Render `<.flash kind={:error} />`.
- **Expected:** The resulting HTML does not contain raw, uncompiled arbitrary modifiers like `/35`.
- **Guards Against:** Invalid arbitrary opacity modifiers (`/35`) failing to compile in Tailwind.

# Implementation Tasks
- [x] Write tests for branding, footer, textarea scroll, and semantic error colors.
- [x] Write integration test for flash message component rendering.
- [x] Update `<title>` in `root.html.heex` and `.brand-wordmark` in `chat_live.ex` to "Threadworks AI".
- [x] Add the footer structure to the bottom of the main layout with 150ms ease hover/focus states.
- [x] Change `<textarea>` style in `chat_live.ex` from `overflow-y: hidden` to `auto`.
- [x] Refactor flash notifications in `core_components.ex` to use `bg-opacity-10` utility.
- [x] Refactor error states in `chat_live.ex` to use `--status-error` / `--status-success` tokens.

# Definition of Done
- [x] All tests pass.
- [x] Mobile manual check: Focus the textarea on an iPhone; ensure the iOS keyboard does not push the footer up over the composer.
