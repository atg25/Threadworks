# Ad-hoc UI Audit After SP-03-18

## Purpose

This note records the manual UI/UX changes that landed after the SP-03-18 scope was considered closed, but outside the normal sprint activation workflow.

Use this file as the preservation record for future Phase 3 sprint work.

## Boundary

- Planning boundary: `SP-03-18` is the latest closed sprint in the project docs.
- Git limitation: `SP-03-18` and the related Phase 3 sprint files are currently untracked in git, so there is no exact commit or tag that marks the sprint close.
- Practical interpretation: this audit describes the ad-hoc changes that shipped after the SP-03-18 scope closed in planning, based on the current application files and test coverage.

## Shipped Ad-hoc Changes

### 1. Desktop sidebar now collapses and starts closed

- Files: `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/live/sidebar_component.ex`
- Change: the desktop sidebar is collapsible and now defaults to collapsed on first load.
- Why: reduce initial visual noise and give the main chat surface more space.

### 2. Header chrome was simplified

- Files: `chat_app/lib/chat_app_web/live/chat_live.ex`
- Change: the old text pills were removed. The shipped header controls are now the hamburger toggle, a square `hero-pencil-square` new-chat button near the wordmark, and the settings gear.
- Why: make the primary actions clearer and reduce redundant controls.

### 3. Model/API chrome above the chat was removed

- Files: `chat_app/lib/chat_app_web/live/chat_live.ex`
- Change: the transient top model strip and API cost box above the transcript were removed.
- Why: they added clutter without improving the core chat flow.

### 4. Named theme selector is now functional

- Files: `chat_app/assets/js/app.js`, `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/components/layouts/root.html.heex`
- Change: the selector now applies the four named themes `editorial`, `swiss`, `mid-century`, and `techno-brutalist` through `<html data-theme>` and persists the choice via `localStorage`.
- Why: the design system theme work is already live and should not regress to the earlier light/dark-only behavior.

### 5. New-chat affordance and hero animation were polished

- Files: `chat_app/lib/chat_app_web/live/chat_live.ex`
- Change: the new-conversation control became a square pencil button, and the hero landing animation after starting a new chat was made more deliberate and obvious.
- Why: make it visually clear that a fresh conversation was created.

### 6. Footer was redesigned and moved below the fold

- Files: `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/components/layouts.ex`, `chat_app/lib/chat_app_web/components/layouts/root.html.heex`
- Change: the footer became a larger, more professional author/project/link section. It now sits below the initial chat viewport and is reached by scrolling a dedicated page shell.
- Why: preserve the immersive full-screen chat shell while keeping the footer available as a lower-page section instead of fixed chrome.

### 7. Local runtime behavior was fixed so chat works during review

- Files: `chat_app/config/runtime.exs`
- Change: local dev now loads `.env` and rejects placeholder OpenAI keys.
- Why: the UI review uncovered a broken `401` path; the runtime fix prevents the chat surface from appearing functional while backend requests fail.

### 8. Tests were updated to preserve the new baseline

- Files: `chat_app/test/chat_app_web/live/chat_live_test.exs`, `chat_app/test/e2e/sprint_17_foundation_updates_e2e_test.exs`
- Change: regression coverage now reflects the header cleanup, footer behavior, theme selector, and new-chat behavior.
- Why: future sprint work needs explicit tests around these ad-hoc changes so they are not accidentally undone.

## Components Most At Risk Of Regression

- `chat_app/lib/chat_app_web/live/chat_live.ex`
- `chat_app/lib/chat_app_web/live/sidebar_component.ex`
- `chat_app/lib/chat_app_web/components/layouts.ex`
- `chat_app/lib/chat_app_web/components/layouts/root.html.heex`
- `chat_app/assets/js/app.js`
- `chat_app/config/runtime.exs`

## Do Not Revert

Future Phase 3 work should treat the following as current baseline behavior:

- Desktop sidebar stays collapsible and default-collapsed.
- Header stays icon-led and does not revert to the older text-pill layout.
- The top model badge and API cost card stay removed.
- The named 4-theme selector stays wired through `data-theme` and `localStorage`.
- The square pencil new-chat affordance and stronger landing animation stay intact unless intentionally replaced by a better tested design.
- The footer stays below the initial viewport and should not be pulled back into the fixed chat shell by restoring global overflow locking.

## Related Docs

- `docs/sprints/complete/SP-03-18-component-polish.md`
- `docs/specs/active/spec-1.md`
- `docs/sprints/complete/SP-03-19A-desktop-layout.md`
- `docs/sprints/complete/SP-03-19B-mobile-drawer.md`
- `docs/sprints/complete/SP-03-20-multi-theme.md`
- `docs/sprints/README.md`
- `docs/README.md`