# Documentation

This folder holds specifications, sprint plans, and reference material for the IS322 final project: a Phoenix LiveView chat console that mirrors the home-page UX of the reference app under `_references/ai_mcp_chat_ordo/`. The runnable application lives in `chat_app/`.

## Where things live

| Area               | Path                                                                   | Purpose                                                                                                   |
| ------------------ | ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Specifications     | [`specs/active/`](specs/active/), [`specs/complete/`](specs/complete/) | Product and technical specs (`spec-1` is the active spec for the initial chat console).                   |
| Sprints            | [`sprints/`](sprints/README.md)                                        | Planned, active, and completed sprint write-ups with YAML `status` in frontmatter.                        |
| Reference codebase | [`_references/ai_mcp_chat_ordo/`](_references/ai_mcp_chat_ordo/)       | Upstream Next.js project used for visual and behavioral parity (not part of the graded deliverable tree). |

## Phase and spec files

- **Phase 1 — Spec 1 (chat console):** [`specs/active/spec-1.md`](specs/active/spec-1.md) — scope for sprints 1.1–1.10 (completed under [`sprints/complete/`](sprints/complete/)). Phase 1 is **complete**.
- **Phase 2 — Audit follow-through (in progress):** **SPRINT-11** (correctness & XSS) is **complete** ([`sprints/complete/SPRINT-11-immediate-fixes-correctness.md`](sprints/complete/SPRINT-11-immediate-fixes-correctness.md)). **SPRINT-12** (resilience, cleanup) is **complete** ([`sprints/complete/SPRINT-12-immediate-fixes-resilience.md`](sprints/complete/SPRINT-12-immediate-fixes-resilience.md)). **In flight:** **SPRINT-13** ([`sprints/active/SPRINT-13-hardening-architecture.md`](sprints/active/SPRINT-13-hardening-architecture.md)). Sprints 14–16 remain in [`sprints/planned/`](sprints/planned/). There is no separate phase spec file; those sprints reference the engineering audit and backlog codes (IF / H / F) in their bodies.

**Overall sprint progress (all phases):** 12 of 16 sprints done (**75%**). Phase 2: 2 of 6 sprints complete, **1 in progress** (SPRINT-13), **3 sprints remaining** in Phase 2 (14–16).

For a single table of every sprint ID, phase label, and status, see **[`sprints/README.md`](sprints/README.md)**.

## Application docs

Project-level docs for the Phoenix app (changelog, architecture notes) are in [`../chat_app/`](../chat_app/) (for example `README.md`, `CHANGELOG.md`, `ARCHITECTURE.md`).
