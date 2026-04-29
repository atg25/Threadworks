---
id: SP-3-18
phase: 3
status: complete
created: Apr-28-2026
activated: Apr-28-2026
completed: Apr-28-2026
---

# Goal

Improve shared UI components and transient empty/loading states.

# Scope

- **In:** Semantic buttons, Heroicons, `.prose` color overrides, skeleton loader, sidebar empty state.
- **Out:** Moving header buttons to corners, making sidebar collapsible.

# Tests

## E2E Happy Path

`test "sidebar displays empty state illustration when zero conversations exist"`

- **Inputs:** Load app with an empty database/state.
- **Expected:** Sidebar contains `<svg>` icon and "No conversations yet" text.
- **Guards Against:** Blank or collapsed sidebars confusing new users.

## E2E Negative 1

`test "assistant markdown inherits theme foreground color"`

- **Inputs:** Stream an assistant message containing headers, paragraphs, and bold text.
- **Expected:** The computed text color of paragraphs and headers exactly matches the inherited `--foreground` color of the container, overriding Tailwind defaults.
- **Guards Against:** Dark mode unreadability due to hardcoded `.prose` colors.

## E2E Negative 2

`test "typing indicator renders as a 3-line skeleton block"`

- **Inputs:** Submit a prompt, intercept stream delay.
- **Expected:** Bouncing dots are absent; a pulsing skeleton block is visible while `is_sending` is true.
- **Guards Against:** Regression to basic unbranded loading dots.

# Implementation Tasks

- [x] Write E2E tests for empty state, markdown color inheritance, and skeleton indicator.
- [x] Update `utilities.css` for `.prose` text inheritance.
- [x] Swap raw text for Heroicons in sidebar.
- [x] Update "Regenerate" and "Copy" buttons in `chat_live.ex` to use `.icon-btn`.
- [x] Remove feedback up/down arrows from message bubbles in `chat_live.ex`.
- [x] Implement sidebar empty state.
- [x] Replace 3-dot animation in `chat_live.ex` with the 3-line skeleton block.

# Definition of Done

- [ ] All tests pass.
- [ ] Manual check: Verify inline `<code>` and block `<pre>` elements retain distinct backgrounds and do not inherit the global `.prose-p` text color.

# Ad-hoc Changes

After SP-03-18 closed, a manual UI/UX pass landed outside the normal sprint activation flow. Treat the following as shipped Phase 3 baseline behavior.

- `chat_app/lib/chat_app_web/live/chat_live.ex`, `chat_app/lib/chat_app_web/live/sidebar_component.ex`: desktop sidebar collapse shipped and now defaults to collapsed on first load; header text pills were removed; the new-conversation control is a square pencil button; the transient top model strip and API cost box were removed; the hero landing animation is deliberately more obvious when starting a new chat. Why: simplify the desktop chrome and make the new-chat affordance clearer.
- `chat_app/assets/js/app.js`: the header theme selector now applies the named themes `editorial`, `swiss`, `mid-century`, and `techno-brutalist` through `<html data-theme>` and persists the selection via `localStorage`. Why: the multi-theme system is already live and should not regress to the earlier light/dark-only behavior.
- `chat_app/lib/chat_app_web/components/layouts/root.html.heex`, `chat_app/lib/chat_app_web/components/layouts.ex`, `chat_app/lib/chat_app_web/live/chat_live.ex`: the page now uses a dedicated scroll shell so the footer sits below the initial chat viewport and appears only after scrolling. The footer itself was expanded into a larger author/project/link section. Why: preserve the full-screen chat feel while giving the page a more professional bottom section.
- `chat_app/config/runtime.exs`: local dev now loads `.env` and rejects placeholder OpenAI keys. Why: keep the chat flow functional during UI review instead of silently regressing to the 401 path.
- `chat_app/test/chat_app_web/live/chat_live_test.exs`, `chat_app/test/e2e/sprint_17_foundation_updates_e2e_test.exs`: regression coverage was updated for the footer, header cleanup, theme selector, and new-chat behavior. Why: future sprint work needs tests around these ad-hoc changes so they are not accidentally undone.
