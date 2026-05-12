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

- **Phase 0 — Foundation (complete):** **SP-00-01** (deps & config, ✅ complete 2026-05-06), **SP-00-02** (core schema migrations 1–4, ✅ complete 2026-05-06), **SP-00-03** (search infra & VectorCodec, ✅ complete 2026-05-06).
- **Phase 1 — Spec 1 (chat console):** [`specs/active/spec-1.md`](specs/active/spec-1.md) — scope for sprints 1.1–1.10 (completed under [`sprints/complete/`](sprints/complete/)). Phase 1 is **complete**.
- **Phase 2 — Audit follow-through (complete):** **SPRINT-11** (correctness & XSS, ✅ complete), **SPRINT-12** (resilience & cleanup, ✅ complete), **SPRINT-13** (hardening: architecture & internals, ✅ complete), **SPRINT-14** (hardening: tooling, docs & governance, ✅ complete), **SPRINT-15** (persistence, auth & first controls, ✅ complete), **SPRINT-16** (feature velocity, ✅ complete).
- **Phase 3 — Polish & Refinement (complete):** **SP-03-17** (foundation updates & bug fixes, ✅ complete); **SP-03-18** (component polish & empty states, ✅ complete); **SP-03-19A** (desktop layout & header refactor, ✅ complete 2026-04-29); **SP-03-19B** (mobile off-canvas drawer, ✅ complete 2026-04-29); **SP-03-20** (multi-theme engine overhaul, ✅ complete 2026-04-29). Note: a later ad-hoc UI pass already delivered part of the original 19A/20 scope and is now the baseline for future work.

**Overall sprint progress (all phases):** 33 of 36 sprints done (**92%**). Phases 0–3 are complete (23 sprints). Phase 4.0 is complete (3 sprints). Phase 4.1 is complete (8 of 8 sprints: SP-01-01 through SP-01-08). Phase 4.2 is in progress (4 of 5 sprints: SP-02-01, SP-02-02, SP-02-03, SP-02-04 complete). Phase 4.3–4.4 are draft.

For a single table of every sprint ID, phase label, and status, see **[`sprints/README.md`](sprints/README.md)**.

## Phase 4 — Threadworks AI Style Consultant

Phase 4 transforms the app into an AI style consultant for second-hand clothing. It is broken into five sequential sub-phases.

| Sub-phase | File | Goal | Complexity | Status |
| --- | --- | --- | --- | --- |
| Overview / dep map | [phases/overview.md](phases/overview.md) | Dependency diagram + locked decisions | — | draft |
| 0 — Foundation | [phases/phase-0-foundation.md](phases/phase-0-foundation.md) | Schema, deps, VectorCodec | S | complete |
| 1 — ETL Pipeline | [phases/phase-1-etl-pipeline.md](phases/phase-1-etl-pipeline.md) | Scrape eBay/Depop/Poshmark, normalize, deduplicate, embed | M | complete |
| 2 — Hybrid Search | [phases/phase-2-hybrid-search.md](phases/phase-2-hybrid-search.md) | Vector + FTS5 + RRF search engine | M | draft |
| 3 — Chat RAG | [phases/phase-3-chat-rag.md](phases/phase-3-chat-rag.md) | Augment prompt, parse card JSON from stream | M | draft |
| 4 — UI | [phases/phase-4-ui.md](phases/phase-4-ui.md) | Product cards, saved items, preferences | L | draft |

**Build order:** 0 → 1 → 2 → 3 → 4. Safe parallelism: Phase 4 saved-items page and preferences form can be scaffolded against Phase 0 schema before Phases 1–3 are complete.

**External credentials needed before Phase 1:** `EBAY_APP_ID`, `EBAY_CERT_ID` (free registration at developer.ebay.com). `OPENAI_API_KEY` already present.

---

## Current Project State

**Phase 0 — Foundation is now complete (2026-05-06):**
- **SP-00-01** ✅ closed (2026-05-06): Dependencies and config baseline — Oban + sqlite_vec installed, configured, and verified in supervision tree; eBay credentials stubbed in .env.example.
- **SP-00-02** ✅ closed (2026-05-06): Core schema migrations (migrations 1–4) with 23/23 passing tests — Oban jobs table, enhanced clothing_items with 8 new columns, price_history with CASCADE FK, and saved_items with nilify_all FK.
- **SP-00-03** ✅ closed (2026-05-06): Search Infra & VectorCodec — migrations 5–7 (user_preferences, FTS5, vec0), VectorCodec little-endian codec, 25/25 tests passing. Critical finding during QA: endianness mismatch detected and fixed (big-endian → little-endian to match sqlite_vec expectations).

**Phase 3 — Polish & Refinement work is complete:**
- **SP-03-20** ✅ closed (2026-04-29): multi-theme engine hardened (named themes, persistence, LiveView-safe behavior, active-state polish, regression tests).
- **SP-03-19B** ✅ closed (2026-04-29): mobile off-canvas sidebar with backdrop, responsive classes, and E2E/contract coverage; additive on the desktop baseline from SP-03-19A.
- **SP-03-19A** ✅ closed (2026-04-29): regression and hardening coverage for desktop sidebar toggle, header accessibility, absence of legacy cost/model chrome, and page-shell scroll invariants are in the test suite.
- Desktop chat layout now ships with a collapsible sidebar that starts collapsed on first load.
- Header chrome is simplified: the old text pills, top model strip, and API cost card are gone; the shipped controls are the hamburger toggle, square pencil new-chat button, and settings gear.
- The named 4-theme selector is live and persists via `<html data-theme>` plus `localStorage`.
- The footer is now a larger professional author/project/link section that lives below the initial chat viewport and is reached by scrolling.

**Phase 4 — Threadworks AI Style Consultant (in progress):**

- **Phase 4.0 — Foundation:** ✅ complete (SP-00-01, SP-00-02, SP-00-03 from old Phase 0; schema and VectorCodec in place).
- **Phase 4.1 — ETL Pipeline (complete):**
  - **SP-01-01** ✅ closed (2026-05-06): Test Infrastructure + Normalizer — 3-source normalizer (eBay, Depop, Poshmark) with condition mapping, price coercion, and full unit test coverage. 29/29 tests passing.
  - **SP-01-02** ✅ closed (2026-05-09): eBay Source Adapter — OAuth client credentials grant, token caching in ETS, mocked search endpoint. 15/15 tests passing.
  - **SP-01-03** ✅ closed (2026-05-10): Depop Source Adapter — HTTP search with Mozilla/5.0 + en-US headers, raw JSON pass-through, nil-field handling. 13/13 tests passing.
  - **SP-01-04** ✅ closed (2026-05-11): Poshmark Source Adapter — HTML scraping with Floki, pure parse_html/2, selector regression test. 16/16 tests passing.
  - **SP-01-05** ✅ closed (2026-05-11): Deduplicator + Price History — upsert/1 with on_conflict replace semantics, atomic PriceHistory write, idempotent batch upsert, custom DecimalString Ecto type for SQLite precision preservation. 15/15 tests passing. **Critical issues found and fixed during QA: transaction atomicity, error handling in batch, migration rollback.**
  - **SP-01-06** ✅ closed (2026-05-11): Scrape Worker (ETL Orchestration) — ScrapeWorker dispatches to all three adapters, normalizes, upserts via Deduplicator, and enqueues batched EmbedWorker jobs in 20-item chunks. 10/10 tests passing. Fixed pre-existing bugs: brand column nullability, Oban prefix config for SQLite, test DB migration. Zero regressions across 547 non-feature tests.
  - **SP-01-07** ✅ closed (2026-05-11): Embed Worker (batch OpenAI embeddings) — EmbedWorker calls Embedder.embed_batch/1 (one HTTP request per 20 items), stores 512-dim binary vectors via VectorCodec in clothing_items.embedding, upserts into clothing_vec, and indexes items into clothing_fts. 11/11 tests passing. Critical issues found and fixed during QA: FTS5Index retry safety (use non-bang query), empty item list guard (early return), idiomatic nil filtering. Zero regressions across 550 non-feature tests.
  - **SP-01-08** ✅ closed (2026-05-11): Scheduler E2E — Oban.Plugins.Cron wired to fire ScrapeWorker on 2-hour cadence; `"queries"` dispatch clause enqueues all source × query combinations. Config eval ordering fixed, arg schema mismatch resolved. 8/8 sprint tests passing. **Critical issues found and fixed during QA: config eval timing (local variable binding), arg schema mismatch (new perform clause), missing cron-path test coverage.**
- **Phase 4.2 — Hybrid Search (in progress):**
  - **SP-02-01** ✅ closed (2026-05-11): Embedder + Test Fixtures — `ChatApp.AI.Embedder.embed/1` and `embed_batch/1` with OpenAI `text-embedding-3-small` (512 dims), L2 normalization, and dimension validation. Three committed fixture vectors (vintage jacket, evening gown, denim jacket) for downstream sprint tests. 14/14 tests passing. **Critical issues found and fixed during QA: nil-embedding handling via `Enum.reduce_while` (not `Enum.find`), out-of-order API response reordering, malformed response guard, test env cleanup via `setup_bypass` `on_exit`.**
  - **SP-02-02** ✅ closed (2026-05-11): QueryProcessor — Lowercase, stopword removal (preserving size terms), synonym expansion with OR grouping, and FTS5 operator safety. Pure-function text normalization pipeline. 19/19 tests passing. **QA review identified 4 spec ambiguities; resolved all with user guidance (lowercase OR, apostrophe stripping, stopword list pruning, per-token escaping timing). No regressions across 599 non-feature tests.** Next sprint dependency ready: FTS5Index implementation.
- **Phases 4.3–4.4:** Chat RAG, UI (draft).

- **SP-02-04** ✅ closed (2026-05-12): FTS5Index — Full-text search with BM25 ranking and delete-then-insert upsert pattern for external content tables. 17/17 tests passing (3 unit, 11 integration, 3 E2E). Fixed critical issues during QA: nil BM25 scores, dual implementation divergence, missing transaction atomicity, overly broad error rescue.

**Next active sprint:** SP-02-05a — HybridEngine Core (Phase 2). See [`phases/overview.md`](phases/overview.md) for dependency map and locked decisions.

## Audit Notes

- Standalone preservation note for the post-SP-03-18 manual UI pass: [`AD-HOC-UI-AUDIT-SP-03-18.md`](AD-HOC-UI-AUDIT-SP-03-18.md)

## Application docs

Project-level docs for the Phoenix app (changelog, architecture notes) are in [`../chat_app/`](../chat_app/) (for example `README.md`, `CHANGELOG.md`, `ARCHITECTURE.md`).
