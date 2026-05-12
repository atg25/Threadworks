---
status: draft
last_updated: 2026-05-06
phase: 4
title: Phase 4 — Threadworks AI Style Consultant — Dependency Map
---

# Phase 4 — Dependency Map

Phase 4 transforms Threadworks from a general AI chat console into an AI style consultant specializing in second-hand clothing. It is organized as five sequential sub-phases (0–4), with one safe parallelism window.

## Sub-Phase Summary

| Sub-phase | Slug | Goal | Complexity | Status |
|---|---|---|---|---|
| 0 | foundation | Schema, deps, VectorCodec | S | draft |
| 1 | etl-pipeline | Scrape → normalize → embed → store | M | draft |
| 2 | hybrid-search | Vector + FTS5 + RRF engine | M | draft |
| 3 | chat-rag | Augment prompt → parse cards | M | draft |
| 4 | ui | Cards, saved items, preferences | L | draft |

## Dependency Diagram

```
Phase 0: Foundation
  (schema, deps, migrations, VectorCodec)
      |
      +------ Phase 1: ETL Pipeline
      |         (scrape, normalize, embed, schedule)
      |              |
      |              +------ Phase 2: Hybrid Search
      |                       (VectorStore, FTS5Index, HybridEngine)
      |                            |
      |                            +------ Phase 3: Chat RAG
      |                                     (StyleAdvisor, ResponseParser,
      |                                      QueryUnderstander, ChatLive update)
      |                                          |
      |                                          +---- Phase 4: Cards + Chat UI
      |                                                (ProductCard, card rendering,
      |                                                 save/unsave handlers)
      |
      +------ Phase 4 (partial): Saved Items + Preferences UI
               (SavedLive, router, UserLive.Settings form)
               Blocked on Phase 0 schema only.
               Can be scaffolded with seed fixtures while 1-3 are in progress.
```

## Key Cross-Phase Decisions

These decisions cut across phase boundaries and must be locked before implementation starts:

| Decision | Locked value |
|---|---|
| Embedding dimensions | 512 (text-embedding-3-small with `dimensions: 512`) |
| Vector serialization | `VectorCodec.encode/decode` (float32 big-endian binary) |
| FTS5 sync mechanism | Explicit calls in EmbedWorker — no triggers |
| EmbedWorker batch size | 20 items per Oban job |
| RRF k constant | 60 |
| Clarification threshold | RRF score >= 0.015 with >= 2 results |
| Deleted item FK behavior | `ON DELETE SET NULL` on saved_items.item_id |
| eBay base URL config | `EBAY_API_BASE_URL` env var (sandbox in dev, prod in prod) |
| HTTP mock strategy | Bypass fixtures for all external HTTP in tests |

## External Credentials Required Before Phase 1

```
EBAY_APP_ID=...        # from developer.ebay.com (free registration)
EBAY_CERT_ID=...       # from developer.ebay.com
EBAY_API_BASE_URL=https://api.sandbox.ebay.com   # dev
OPENAI_API_KEY=...     # already present in project
```

## Safe Parallelism

After Phase 0 is merged:
- Phase 4 saved items page (`SavedLive`) and preferences form can be scaffolded using factory-seeded `clothing_items` and `saved_items` data
- All other sub-phases must complete in order (1 → 2 → 3 → 4 card rendering)
