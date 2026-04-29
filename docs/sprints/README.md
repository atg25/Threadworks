# Sprints

Sprint plans live under `planned/` until work starts; the sprint in flight is under `active/`; finished sprint records live under `complete/`. Each file has YAML frontmatter with `status: planned`, `status: active`, or `status: complete`.

## Sprint index

| Sprint ID | Phase                                                  | Status   | Document                                                                                      |
| --------- | ------------------------------------------------------ | -------- | --------------------------------------------------------------------------------------------- |
| 1.1       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.1.md](complete/sprint-1.1.md)                                                       |
| 1.2       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.2.md](complete/sprint-1.2.md)                                                       |
| 1.3       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.3.md](complete/sprint-1.3.md)                                                       |
| 1.4       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.4.md](complete/sprint-1.4.md)                                                       |
| 1.5       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.5.md](complete/sprint-1.5.md)                                                       |
| 1.6       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.6.md](complete/sprint-1.6.md)                                                       |
| 1.7       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.7.md](complete/sprint-1.7.md)                                                       |
| 1.8       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.8.md](complete/sprint-1.8.md)                                                       |
| 1.9       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.9.md](complete/sprint-1.9.md)                                                       |
| 1.10      | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.10.md](complete/sprint-1.10.md)                                                     |
| 11        | Phase 2 — Immediate fixes (correctness & XSS)          | complete | [SPRINT-11-immediate-fixes-correctness.md](complete/SPRINT-11-immediate-fixes-correctness.md) |
| 12        | Phase 2 — Immediate fixes (resilience & cleanup)       | complete | [SPRINT-12-immediate-fixes-resilience.md](complete/SPRINT-12-immediate-fixes-resilience.md)   |
| 13        | Phase 2 — Hardening (architecture & internals)         | complete | [SPRINT-13-hardening-architecture.md](complete/SPRINT-13-hardening-architecture.md)           |
| 14        | Phase 2 — Hardening (tooling, docs & governance)       | complete | [SPRINT-14-hardening-tooling.md](complete/SPRINT-14-hardening-tooling.md)                     |
| 15        | Phase 2 — Persistence, auth & first controls           | complete | [SPRINT-15-persistence-and-auth.md](complete/SPRINT-15-persistence-and-auth.md)               |
| 16        | Phase 2 — Feature velocity (sidebar, settings, polish) | complete | [SPRINT-16-feature-velocity.md](complete/SPRINT-16-feature-velocity.md)                       |
| 17        | Phase 3 — Foundation Updates & Bug Fixes               | complete | [SP-03-17-foundation-updates.md](complete/SP-03-17-foundation-updates.md)                   |
| 18        | Phase 3 — Component Polish & Empty States              | complete | [SP-03-18-component-polish.md](complete/SP-03-18-component-polish.md)                       |
| 19A       | Phase 3 — Desktop Layout & Header Refactor             | complete (2026-04-29) | [SP-03-19A-desktop-layout.md](complete/SP-03-19A-desktop-layout.md)                         |
| 19B       | Phase 3 — Mobile Off-Canvas Drawer                     | complete (2026-04-29) | [SP-03-19B-mobile-drawer.md](complete/SP-03-19B-mobile-drawer.md)                         |
| 20        | Phase 3 — Multi-Theme Engine Overhaul                  | complete (2026-04-29) | [SP-03-20-multi-theme.md](complete/SP-03-20-multi-theme.md)                               |

## Folders

- **`complete/`** — Sprints 1.1–1.10 (spec-1 delivery), **SPRINT-11**, **SPRINT-12**, **SPRINT-13**, **SPRINT-14**, **SPRINT-15**, **SPRINT-16**, **SP-03-17**, **SP-03-18**, **SP-03-19A**, **SP-03-19B**, **SP-03-20**.
- **`planned/`** — None.
- **`active/`** — None.

## Phase Progress

- **Phase 1:** Complete (10 of 10).
- **Phase 2:** Complete (6 of 6).
- **Phase 3:** Complete (5 of 5).

## Current Phase 3 Baseline

An ad-hoc UI pass landed after SP-03-18 and already delivered part of the original 19A/20 scope: the desktop-collapsible sidebar, cleaned-up header icon controls, removal of the top model/API chrome, the named 4-theme selector, and the below-fold footer shell. Phase 3 sprints (through SP-03-20) extended and hardened that baseline rather than reintroducing the older UI.
