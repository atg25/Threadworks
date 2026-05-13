# Documentation

This folder holds specifications, sprint plans, and reference material for the IS322 final project: a Phoenix LiveView chat console that mirrors the home-page UX of the reference app under `_references/ai_mcp_chat_ordo/`. The runnable application lives in `chat_app/`.

## Where things live

| Area               | Path                                                                   | Purpose                                                                                                   |
| ------------------ | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Specifications     | [`specs/active/`](specs/active/), [`specs/complete/`](specs/complete/) | Product and technical specs (`spec-1` is the active spec for the initial chat console).                   |
| Sprints            | [`sprints/`](sprints/README.md)                                        | Planned, active, and completed sprint write-ups with YAML `status` in frontmatter.                        |
| Phase tracking     | [`phases/phase-3.md`](phases/phase-3.md)                               | Phase 3 deliverable checklist (polish & refinement; complete).                                            |
| Reference codebase | [`_references/ai_mcp_chat_ordo/`](_references/ai_mcp_chat_ordo/)       | Upstream Next.js project used for visual and behavioral parity (not part of the graded deliverable tree). |

## Phase and spec files

- **Phase 1 — Spec 1 (chat console):** [`specs/active/spec-1.md`](specs/active/spec-1.md) — scope for sprints 1.1–1.10 (completed under [`sprints/complete/`](sprints/complete/)). Phase 1 is **complete**.
- **Phase 2 — Audit follow-through (complete):** **SPRINT-11** (correctness & XSS, ✅ complete), **SPRINT-12** (resilience & cleanup, ✅ complete), **SPRINT-13** (hardening: architecture & internals, ✅ complete), **SPRINT-14** (hardening: tooling, docs & governance, ✅ complete), **SPRINT-15** (persistence, auth & first controls, ✅ complete), **SPRINT-16** (feature velocity, ✅ complete).
- **Phase 3 — Polish & Refinement (complete):** **SP-03-17** (foundation updates & bug fixes, ✅ complete); **SP-03-18** (component polish & empty states, ✅ complete); **SP-03-19A** (desktop layout & header refactor, ✅ complete 2026-04-29); **SP-03-19B** (mobile off-canvas drawer, ✅ complete 2026-04-29); **SP-03-20** (multi-theme engine overhaul, ✅ complete 2026-04-29). Note: a later ad-hoc UI pass already delivered part of the original 19A/20 scope and is now the baseline for future work.

**Overall sprint progress (all phases):** 46 of 47 sprints done (**98%**). Phases 0–4 complete; Phase 5 in progress (5 of 6 sprint records complete).

For a single table of every sprint ID, phase label, and status, see **[`sprints/README.md`](sprints/README.md)**.

## Current Project State

- **SP-05-01** is closed (2026-05-12): ProductCard HEEx component with image fallback, price formatting, condition humanization, escape + sanitization (XSS, atom-table DoS, javascript: URIs), and regression test coverage. 3 security issues fixed during final QA.
- **SP-05-04b** is closed (2026-05-13): ChatLive streaming card attach and refresh-listings job enqueueing now work end to end, with reload-safe card persistence.
- **SP-05-04a** is closed (2026-05-13): ChatLive save/unsave event handlers now hydrate saved-item state and persist toggles cleanly.
- **SP-05-03** is closed (2026-05-13): authenticated saved-items LiveView at `/saved` with source filtering, price delta badges, and listing-removed handling.
- **Phase 4 (Chat RAG)** is closed: prompt builder, response parser, style advisor, ChatLive pipeline integration, and card rendering complete across 5 sprints (SP-04-01 through SP-04-05).
- **Phase 3 polish** is complete; the chat UI baseline has collapsible sidebar, simplified header, named 4-theme selector with persistence, professional footer section, and full accessibility audit coverage.
- **Phase 5 (UI)** is in progress: next sprint is SP-05-05 (User preferences).

## Audit Notes

- Standalone preservation note for the post-SP-03-18 manual UI pass: [`AD-HOC-UI-AUDIT-SP-03-18.md`](AD-HOC-UI-AUDIT-SP-03-18.md)

## Application docs

Project-level docs for the Phoenix app (changelog, architecture notes) are in [`../chat_app/`](../chat_app/) (for example `README.md`, `CHANGELOG.md`, `ARCHITECTURE.md`).
