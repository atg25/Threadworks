# Documentation

This folder holds specifications, sprint plans, and reference material for the IS322 final project: a Phoenix LiveView chat console that mirrors the home-page UX of the reference app under `_references/ai_mcp_chat_ordo/`. The runnable application lives in `chat_app/`.

## Where things live

| Area               | Path                                                                   | Purpose                                                                                                   |
| ------------------ | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Specifications     | [`specs/active/`](specs/active/), [`specs/complete/`](specs/complete/) | Product and technical specs (`spec-1` is the active spec for the initial chat console).                   |
| Sprints            | [`sprints/`](sprints/README.md)                                        | Planned, active, and completed sprint write-ups with YAML `status` in frontmatter.                        |
| Phase tracking     | [`phases/phase-3.md`](phases/phase-3.md)                               | Phase 3 deliverable checklist (polish & refinement; complete).                                          |
| Reference codebase | [`_references/ai_mcp_chat_ordo/`](_references/ai_mcp_chat_ordo/)       | Upstream Next.js project used for visual and behavioral parity (not part of the graded deliverable tree). |

## Phase and spec files

- **Phase 1 — Spec 1 (chat console):** [`specs/active/spec-1.md`](specs/active/spec-1.md) — scope for sprints 1.1–1.10 (completed under [`sprints/complete/`](sprints/complete/)). Phase 1 is **complete**.
- **Phase 2 — Audit follow-through (complete):** **SPRINT-11** (correctness & XSS, ✅ complete), **SPRINT-12** (resilience & cleanup, ✅ complete), **SPRINT-13** (hardening: architecture & internals, ✅ complete), **SPRINT-14** (hardening: tooling, docs & governance, ✅ complete), **SPRINT-15** (persistence, auth & first controls, ✅ complete), **SPRINT-16** (feature velocity, ✅ complete).
- **Phase 3 — Polish & Refinement (complete):** **SP-03-17** (foundation updates & bug fixes, ✅ complete); **SP-03-18** (component polish & empty states, ✅ complete); **SP-03-19A** (desktop layout & header refactor, ✅ complete 2026-04-29); **SP-03-19B** (mobile off-canvas drawer, ✅ complete 2026-04-29); **SP-03-20** (multi-theme engine overhaul, ✅ complete 2026-04-29). Note: a later ad-hoc UI pass already delivered part of the original 19A/20 scope and is now the baseline for future work.

**Overall sprint progress (all phases):** 21 of 21 sprints done (**100%**). Phases 1–3 are complete as tracked in [`sprints/README.md`](sprints/README.md).

For a single table of every sprint ID, phase label, and status, see **[`sprints/README.md`](sprints/README.md)**.

## Current Project State

- **SP-03-20** is closed (2026-04-29): multi-theme engine hardened (named themes, persistence, LiveView-safe behavior, active-state polish, regression tests).
- **SP-03-19B** is closed (2026-04-29): mobile off-canvas sidebar with backdrop, responsive classes, and E2E/contract coverage; additive on the desktop baseline from SP-03-19A.
- **SP-03-19A** is closed (2026-04-29): regression and hardening coverage for desktop sidebar toggle, header accessibility, absence of legacy cost/model chrome, and page-shell scroll invariants are in the test suite.
- Desktop chat layout now ships with a collapsible sidebar that starts collapsed on first load.
- Header chrome is simplified: the old text pills, top model strip, and API cost card are gone; the shipped controls are the hamburger toggle, square pencil new-chat button, and settings gear.
- The named 4-theme selector is live and persists via `<html data-theme>` plus `localStorage`.
- The footer is now a larger professional author/project/link section that lives below the initial chat viewport and is reached by scrolling.
- Phase 3 polish work is complete; future enhancements should preserve the current UI baseline and treat those behaviors as already shipped.

## Audit Notes

- Standalone preservation note for the post-SP-03-18 manual UI pass: [`AD-HOC-UI-AUDIT-SP-03-18.md`](AD-HOC-UI-AUDIT-SP-03-18.md)

## Application docs

Project-level docs for the Phoenix app (changelog, architecture notes) are in [`../chat_app/`](../chat_app/) (for example `README.md`, `CHANGELOG.md`, `ARCHITECTURE.md`).
