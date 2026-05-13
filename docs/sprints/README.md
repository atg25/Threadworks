# Sprints

Table of planned sprints for Phase 5 UI work.

| sprint ID | phase | slug                | status   |
| --------- | ----: | ------------------- | -------- |
| SP-05-01  |     5 | product-card        | complete |
| SP-05-02  |     5 | saved-backend       | complete |
| SP-05-03  |     5 | saved-page          | complete |
| SP-05-04a |     5 | chat-save-unsave    | complete |
| SP-05-04b |     5 | chat-stream-refresh | complete |
| SP-05-05  |     5 | preferences         | active   |

Planned sprint files live in `docs/sprints/planned/`.

# Sprints

Sprint plans live under `planned/` until work starts; the sprint in flight is under `active/`; finished sprint records live under `complete/`. Each file has YAML frontmatter with `status: planned`, `status: active`, or `status: complete`.

## Sprint index

| Sprint ID | Phase                                                  | Status   | Document                                                                                        |
| --------- | ------------------------------------------------------ | -------- | ----------------------------------------------------------------------------------------------- |
| 1.1       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.1.md](complete/sprint-1.1.md)                                                         |
| 1.2       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.2.md](complete/sprint-1.2.md)                                                         |
| 1.3       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.3.md](complete/sprint-1.3.md)                                                         |
| 1.4       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.4.md](complete/sprint-1.4.md)                                                         |
| 1.5       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.5.md](complete/sprint-1.5.md)                                                         |
| 1.6       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.6.md](complete/sprint-1.6.md)                                                         |
| 1.7       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.7.md](complete/sprint-1.7.md)                                                         |
| 1.8       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.8.md](complete/sprint-1.8.md)                                                         |
| 1.9       | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.9.md](complete/sprint-1.9.md)                                                         |
| 1.10      | Phase 1 — Spec 1 implementation                        | complete | [sprint-1.10.md](complete/sprint-1.10.md)                                                       |
| 11        | Phase 2 — Immediate fixes (correctness & XSS)          | complete | [SPRINT-11-immediate-fixes-correctness.md](complete/SPRINT-11-immediate-fixes-correctness.md)   |
| 12        | Phase 2 — Immediate fixes (resilience & cleanup)       | complete | [SPRINT-12-immediate-fixes-resilience.md](complete/SPRINT-12-immediate-fixes-resilience.md)     |
| 13        | Phase 2 — Hardening (architecture & internals)         | complete | [SPRINT-13-hardening-architecture.md](complete/SPRINT-13-hardening-architecture.md)             |
| 14        | Phase 2 — Hardening (tooling, docs & governance)       | complete | [SPRINT-14-hardening-tooling.md](complete/SPRINT-14-hardening-tooling.md)                       |
| 15        | Phase 2 — Persistence, auth & first controls           | complete | [SPRINT-15-persistence-and-auth.md](complete/SPRINT-15-persistence-and-auth.md)                 |
| 16        | Phase 2 — Feature velocity (sidebar, settings, polish) | complete | [SPRINT-16-feature-velocity.md](complete/SPRINT-16-feature-velocity.md)                         |
| 17        | Phase 3 — Foundation Updates & Bug Fixes               | complete | [SP-03-17-foundation-updates.md](complete/SP-03-17-foundation-updates.md)                       |
| 18        | Phase 3 — Component Polish & Empty States              | complete | [SP-03-18-component-polish.md](complete/SP-03-18-component-polish.md)                           |
| 19A       | Phase 3 — Desktop Layout & Header Refactor             | complete | [SP-03-19A-desktop-layout.md](complete/SP-03-19A-desktop-layout.md)                             |
| 19B       | Phase 3 — Mobile Off-Canvas Drawer                     | complete | [SP-03-19B-mobile-drawer.md](complete/SP-03-19B-mobile-drawer.md)                               |
| 20        | Phase 3 — Multi-Theme Engine Overhaul                  | complete | [SP-03-20-multi-theme.md](complete/SP-03-20-multi-theme.md)                                     |
| SP-00-01  | Phase 0 — Deps & Config Baseline                       | complete | [SP-00-01-deps-and-config.md](complete/SP-00-01-deps-and-config.md)                             |
| SP-00-02  | Phase 0 — Core Schema Migrations (1–4)                 | complete | [SP-00-02-core-schema-migrations.md](complete/SP-00-02-core-schema-migrations.md)               |
| SP-00-03  | Phase 0 — Search Infra & VectorCodec                   | complete | [SP-00-03-search-infra-and-vector-codec.md](complete/SP-00-03-search-infra-and-vector-codec.md) |
| SP-01-01  | Phase 1 — Test Infrastructure + Normalizer             | complete | [SP-01-01-normalizer.md](complete/SP-01-01-normalizer.md)                                       |
| SP-01-02  | Phase 1 — eBay Source Adapter                          | complete | [SP-01-02-ebay-adapter.md](complete/SP-01-02-ebay-adapter.md)                                   |
| SP-01-03  | Phase 1 — Depop Source Adapter                         | complete | [SP-01-03-depop-adapter.md](complete/SP-01-03-depop-adapter.md)                                 |
| SP-01-04  | Phase 1 — Poshmark Source Adapter                      | complete | [SP-01-04-poshmark-adapter.md](complete/SP-01-04-poshmark-adapter.md)                           |
| SP-01-05  | Phase 1 — Deduplicator + Price History                 | complete | [SP-01-05-deduplicator.md](complete/SP-01-05-deduplicator.md)                                   |
| SP-01-06  | Phase 1 — Scrape Worker (ETL Orchestration)            | complete | [SP-01-06-scrape-worker.md](complete/SP-01-06-scrape-worker.md)                                 |
| SP-01-07  | Phase 1 — Embed Worker (batch OpenAI embeddings)       | complete | [SP-01-07-embed-worker.md](complete/SP-01-07-embed-worker.md)                                   |
| SP-01-08  | Phase 1 — Scheduler + Full E2E                         | complete | [SP-01-08-scheduler-e2e.md](complete/SP-01-08-scheduler-e2e.md)                                 |
| SP-02-01  | Phase 2 (Hybrid Search) — Embedder + Test Fixtures     | complete | [SP-02-01-embedder-fixtures.md](complete/SP-02-01-embedder-fixtures.md)                         |
| SP-02-02  | Phase 2 (Hybrid Search) — QueryProcessor               | complete | [SP-02-02-query-processor.md](complete/SP-02-02-query-processor.md)                             |
| SP-02-03  | Phase 2 (Hybrid Search) — VectorStore                  | complete | [SP-02-03-vector-store.md](complete/SP-02-03-vector-store.md)                                   |
| SP-02-04  | Phase 2 (Hybrid Search) — FTS5Index                    | complete | [SP-02-04-fts5-index.md](complete/SP-02-04-fts5-index.md)                                       |
| SP-02-05a | Phase 2 (Hybrid Search) — HybridEngine Core            | complete | [SP-02-05a-hybrid-engine-core.md](complete/SP-02-05a-hybrid-engine-core.md)                     |
| SP-02-05b | Phase 2 (Hybrid Search) — Filter Opts + Public API     | complete | [SP-02-05b-filter-opts-public-api.md](complete/SP-02-05b-filter-opts-public-api.md)             |
| SP-04-01  | Phase 4 (Chat RAG) — Prompt Builder + Query Evaluator  | complete | [SP-04-01-prompt-builder-and-evaluator.md](complete/SP-04-01-prompt-builder-and-evaluator.md)   |
| SP-04-02  | Phase 4 (Chat RAG) — ResponseParser                    | complete | [SP-04-02-response-parser.md](complete/SP-04-02-response-parser.md)                             |
| SP-04-03  | Phase 4 (Chat RAG) — StyleAdvisor.augment/2            | complete | [SP-04-03-style-advisor-augment.md](complete/SP-04-03-style-advisor-augment.md)                 |
| SP-04-04  | Phase 4 (Chat RAG) — ChatLive RAG Pipeline             | complete | [SP-04-04-chatlive-rag-pipeline.md](complete/SP-04-04-chatlive-rag-pipeline.md)                 |
| SP-04-05  | Phase 4 (Chat RAG) — Card Rendering + Smoke Test       | complete | [SP-04-05-card-rendering-and-smoke.md](complete/SP-04-05-card-rendering-and-smoke.md)           |
| SP-05-01  | Phase 5 (UI) — ProductCard component                   | complete | [SP-05-01-product-card.md](complete/SP-05-01-product-card.md)                                   |

## Folders

- **`complete/`** — Sprints 1.1–1.10 (spec-1 delivery), **SPRINT-11**, **SPRINT-12**, **SPRINT-13**, **SPRINT-14**, **SPRINT-15**, **SPRINT-16**, **SP-03-17**, **SP-03-18**, **SP-03-19A**, **SP-03-19B**, **SP-03-20**, **SP-00-01**, **SP-00-02**, **SP-00-03**, **SP-01-01**, **SP-01-02**, **SP-01-03**, **SP-01-04**, **SP-01-05**, **SP-01-06**, **SP-01-07**, **SP-01-08**, **SP-02-01**, **SP-02-02**, **SP-02-03**, **SP-02-04**, **SP-02-05a**, **SP-02-05b**, **SP-04-01**, **SP-04-02**, **SP-04-03**, **SP-04-04**, **SP-04-05**, **SP-05-01**, **SP-05-02**, **SP-05-03**, **SP-05-04a**, **SP-05-04b**.
- **`planned/`** — none.
- **`active/`** — **SP-05-05**.

## Phase Progress

- **Phase 0:** Complete (3 of 3 sprints complete).
- **Phase 1:** Complete (8 of 8 sprints complete: SP-01-01 through SP-01-08).
- **Phase 2 (Hybrid Search):** Complete (6 of 6 sprints complete: SP-02-01 through SP-02-05b).
- **Phase 3:** Complete (5 of 5).
- **Phase 4 (Chat RAG):** Complete (5 of 5 sprints complete: SP-04-01, SP-04-02, SP-04-03, SP-04-04, SP-04-05 done).
- **Phase 5 (UI):** In progress (5 of 6 sprints complete: SP-05-01, SP-05-02, SP-05-03, SP-05-04a, and SP-05-04b done; SP-05-05 active).

## Phase 5 (UI) Execution Order

SP-05-01 (ProductCard) is complete. SP-05-02 (Saved item backend) is complete. SP-05-03 (Saved items page) is complete. SP-05-04a (ChatLive save/unsave) is complete. SP-05-04b (ChatLive streaming attach & refresh) is complete. SP-05-05 (User preferences) has no direct dependencies on the other Phase 5 sprints.

```text
SP-05-01 ───┐
SP-05-02 ───┼──▶ SP-05-03
            └──▶ SP-05-04a
SP-05-04b ───▶ (complete; depended on SP-05-01 and SP-05-02, both complete)
SP-05-05 ───▶ (independent)
```

## Phase 4 (Chat RAG) Execution Order

SP-04-01 and SP-04-02 have no dependencies and can run in parallel. SP-04-03 is blocked on SP-04-01 (`build_prompt/2` must exist before `augment/2` can call it). SP-04-04 is blocked on SP-04-01, SP-04-02, and SP-04-03 (all three modules are called from ChatLive). SP-04-05 is blocked on SP-04-04 (card rendering requires the socket state pipeline to be working).

```text
SP-04-01 ──┬──▶ SP-04-03 ──┐
SP-04-02 ──┘               ├──▶ SP-04-04 ──▶ SP-04-05
           └───────────────┘
```

Key decisions locked in each sprint that downstream sprints depend on:

- **SP-04-02** locks: `item_id` coercion to integer; trailing text preserved in remaining buffer.
- **SP-04-03** locks: token budget passed as `conversation_tokens:` parameter (not DB read inside `augment/2`); `augment/2` always returns `{:ok, _, _}`, never an error tuple.
- **SP-04-04** locks: async `handle_event` pattern (`send(self(), {:do_rag, text})`); `pending_cards` struct shape (`%{item: %ClothingItem{}, reason: String.t()}`).

## Current Phase 3 Baseline

An ad-hoc UI pass landed after SP-03-18 and already delivered part of the original 19A/20 scope: the desktop-collapsible sidebar, cleaned-up header icon controls, removal of the top model/API chrome, the named 4-theme selector, and the below-fold footer shell. Phase 3 sprints (through SP-03-20) extended and hardened that baseline rather than reintroducing the older UI.
