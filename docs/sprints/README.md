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
| 14        | Phase 2 — Hardening (tooling, docs & governance)       | active   | [SPRINT-14-hardening-tooling.md](active/SPRINT-14-hardening-tooling.md)                       |
| 15        | Phase 2 — Persistence, auth & first controls           | planned  | [SPRINT-15-persistence-and-auth.md](planned/SPRINT-15-persistence-and-auth.md)                |
| 16        | Phase 2 — Feature velocity (sidebar, settings, polish) | planned  | [SPRINT-16-feature-velocity.md](planned/SPRINT-16-feature-velocity.md)                        |

## Folders

- **`complete/`** — Sprints 1.1–1.10 (spec-1 delivery), **SPRINT-11** and **SPRINT-12** (Phase 2 immediate fixes). Older Phase 2 closed sprint records may also live here.
- **`planned/`** — Sprints 14–16 (audit follow-on). Activate the next one into a working branch / `active/` when starting; see **SPRINT-14** for the next up.
- **`active/`** — **SPRINT-13** (hardening: architecture & internals).

## Phase 2 at a glance

- **In progress** — SPRINT-13 ([active](active/SPRINT-13-hardening-architecture.md)). **Done so far:** SPRINT-11, SPRINT-12 (2 of 6 Phase 2 sprints). **Next up:** SPRINT-14 ([planned](planned/SPRINT-14-hardening-tooling.md)).
- There is no separate phase spec; Phase 2 sprints reference the engineering audit and backlog codes (IF / H / F) in their bodies.
