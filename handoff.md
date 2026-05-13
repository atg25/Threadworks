**Handoff: ChatApp — Demo / RAG / LiveView**

**Executive Summary**

- **Purpose:** Provide a self-contained handoff describing the current demo-ready state of the ChatApp repository, how to run it locally, the demo/hybrid-RAG architecture, recent changes, known issues, and next-steps to finish polish.
- **Status:** App compiles and runs locally. Demo seed task available and executed. Frontend assets built. Backend tests compile/run. Demo fallback HTML generated.

**Goals & Context**

- **Primary goal:** Prepare a reliable, offline-capable CEO demo in Hybrid Demo mode with LiveView UI, SQLite persistence, RAG/vector retrieval, and deterministic fallback responses.
- **Recent focus:** Make product cards look better and use real pictures for the demo UI.

**Repository Entry Points**

- **App root:** [chat_app](chat_app)
- **Demo seed task:** [lib/mix/tasks/demo.seed.ex](lib/mix/tasks/demo.seed.ex)
- **Demo catalog / seeded items:** [lib/chat_app/demo.ex](lib/chat_app/demo.ex)
- **Deterministic demo assistant stub:** [lib/chat_app/openai/demo_stub.ex](lib/chat_app/openai/demo_stub.ex)
- **LiveView main:** [lib/chat_app_web/live/chat_live.ex](lib/chat_app_web/live/chat_live.ex)
- **HEEx product card component:** [lib/chat_app_web/components/product_card_component.ex](lib/chat_app_web/components/product_card_component.ex)
- **String-render product card fallback:** [lib/chat_app_web/components/product_card.ex](lib/chat_app_web/components/product_card.ex)
- **Hybrid search engine:** [lib/chat_app/search/hybrid_engine.ex](lib/chat_app/search/hybrid_engine.ex)
- **Vector store:** [lib/chat_app/search/vector_store.ex](lib/chat_app/search/vector_store.ex)
- **FTS5 index:** [lib/chat_app/search/fts5_index.ex](lib/chat_app/search/fts5_index.ex)
- **Dev-only demo login route:** [lib/chat_app_web/router.ex](lib/chat_app_web/router.ex) and [lib/chat_app_web/controllers/dev_controller.ex](lib/chat_app_web/controllers/dev_controller.ex)
- **Static demo fallback (generated):** [priv/static/demo_fallback.html](priv/static/demo_fallback.html)

**Environment & Prereqs**

- **OS:** macOS (dev environment used during development).
- **Languages/Tools:** Elixir (1.19.x), Mix, Phoenix, Node (for assets), SQLite (exqlite). Ensure `mix`, `node`, and `npm` are installed.

**How to run locally (quick)**

- From repository root run:

```bash
cd chat_app
# Install deps if needed
mix deps.get
cd assets && npm install && cd ..
# Build assets (production-style)
mix assets.build
# Seed demo data (dev-only)
MIX_ENV=dev mix demo.seed
# Start server
MIX_ENV=dev mix phx.server
```

**How to run tests / compile**

```bash
cd chat_app
# Compile for test
MIX_ENV=test mix deps.get --only test
MIX_ENV=test mix compile
MIX_ENV=test mix test --color
cd assets && npm test
```

**Demo Mode Details**

- Demo mode is orchestrated via `ChatApp.Demo` in [lib/chat_app/demo.ex](lib/chat_app/demo.ex). When demo is enabled, the app will use `ChatApp.OpenAI.DemoStub` instead of live OpenAI calls for deterministic assistant responses.
- The dev login route `/dev/demo-login` toggles demo mode and ensures the seeded demo user/data exists. See [lib/chat_app_web/controllers/dev_controller.ex](lib/chat_app_web/controllers/dev_controller.ex).
- `mix demo.seed` inserts demo clothing items, upserts FTS rows and vector rows (via sqlite_vec), seeds save preferences, and creates a predictable dataset for demo queries.

**Search / RAG Architecture (high-level)**

- Query embedding: `ChatApp.Embedder` (wire-up) is used to embed text; embeddings feed into the SQLite vector table managed by `ChatApp.Search.VectorStore` ([lib/chat_app/search/vector_store.ex](lib/chat_app/search/vector_store.ex)).
- Keyword fallback: `ChatApp.Search.FTS5Index` provides FTS5-based keyword match fallback.
- Fusion: `ChatApp.Search.HybridEngine` calls vector and FTS searches in parallel and fuses results with reciprocal rank fusion (RRf) to produce final retrievals. See [lib/chat_app/search/hybrid_engine.ex](lib/chat_app/search/hybrid_engine.ex).

**Frontend & Product Cards**

- Primary product card is a LiveView/HEEx component in [lib/chat_app_web/components/product_card_component.ex](lib/chat_app_web/components/product_card_component.ex). It uses Tailwind classes and provides Save/View actions.
- There is also a string-based fallback renderer at [lib/chat_app_web/components/product_card.ex](lib/chat_app_web/components/product_card.ex), used in non-HEEx contexts (and for generating static fallback HTML). A recent syntax error was fixed in that file (inline `if` in iolist moved to precomputed strings).

**Recent Changes & Rationale**

- Updated `@items` in [lib/chat_app/demo.ex](lib/chat_app/demo.ex) to use higher-quality external image URLs for better-looking cards in demos.
- Revamped HEEx `product_card` layout and style to present larger thumbnails, clearer price/source line, and Save/Unsave affordances.
- Updated string-render fallback to match visual design; fixed a compilation SyntaxError caused by inline `if` statements inside an iolist by precomputing button text variables. The fix is in [lib/chat_app_web/components/product_card.ex](lib/chat_app_web/components/product_card.ex).
- Generated a static fallback page (`priv/static/demo_fallback.html`) using a mix run snippet to render several demo cards for offline fallback.

**Known Issues / Notes**

- External images: Demo images were switched to external `https://picsum.photos/...` URLs. If running a demo in an environment without outbound internet access, images will fail to load; recommended to add a small set of committed demo JPEGs under `priv/static/images/demo/` and switch `demo.ex` to point at them.
- Minor compile warnings: `product_card.ex` currently generates harmless unused-variable warnings for `brand` and `size`. They are safe to remove or rename to `_brand`, `_size` if desired.
- OpenAI integration: In non-demo mode, live API calls may timeout during CI or when API keys/rate limits are missing. Demo stub avoids this for demos.

**How static fallback was generated**
The fallback HTML used the following form to render and write HTML to `priv/static/demo_fallback.html`:

```bash
cd chat_app
MIX_ENV=dev mix run -e 'ids = ChatApp.Demo.scripted_card_ids("Find me a vintage denim jacket under $100 that works with streetwear.", 4); html = ChatApp.Demo.render_demo_cards(ids); File.write!("priv/static/demo_fallback.html", html)'
```

**Immediate Next Steps (recommended)**

- Add offline demo images: create `priv/static/images/demo/` and add 8–12 JPEGs; update `@items` in [lib/chat_app/demo.ex](lib/chat_app/demo.ex) to point to them (this ensures demo works without internet).
- Visual polish pass: adjust spacing/typography/colors in [lib/chat_app_web/components/product_card_component.ex](lib/chat_app_web/components/product_card_component.ex) and Tailwind config to match brand.
- Add a small e2e smoke test that hits `/dev/demo-login`, navigates to the chat UI, requests a scripted query, and verifies rendered card count and Save/Unsave buttons.
- Consider bundling `priv/static/demo_fallback.html` into the release or packaging step for deterministic offline demos.

**Troubleshooting Quick Tips**

- If compile fails after edits, run:

```bash
cd chat_app
MIX_ENV=test mix compile --force
```

- To manually render a single product card for visual QA:

```bash
cd chat_app
MIX_ENV=test mix run -e 'item = %{id: 9999, title: "Dev Jacket", brand: "Acme", size: "L", condition: "good", price: Decimal.new("49.99"), source: "store", url: "https://example.com/dev/1", image_url: nil}; rendered = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: "Dev QA placeholder"}); File.mkdir_p!("tmp"); File.write!("tmp/product_card.html", Phoenix.HTML.safe_to_string(rendered)); IO.puts("WROTE tmp/product_card.html")'
open tmp/product_card.html
```

**Files of Interest (quick links)**

- Demo seed & catalog: [lib/mix/tasks/demo.seed.ex](lib/mix/tasks/demo.seed.ex), [lib/chat_app/demo.ex](lib/chat_app/demo.ex)
- Demo stub: [lib/chat_app/openai/demo_stub.ex](lib/chat_app/openai/demo_stub.ex)
- LiveView entry: [lib/chat_app_web/live/chat_live.ex](lib/chat_app_web/live/chat_live.ex)
- Product card HEEx: [lib/chat_app_web/components/product_card_component.ex](lib/chat_app_web/components/product_card_component.ex)
- Product card fallback: [lib/chat_app_web/components/product_card.ex](lib/chat_app_web/components/product_card.ex)
- Hybrid search: [lib/chat_app/search/hybrid_engine.ex](lib/chat_app/search/hybrid_engine.ex)
- Vector store: [lib/chat_app/search/vector_store.ex](lib/chat_app/search/vector_store.ex)
- FTS5 index: [lib/chat_app/search/fts5_index.ex](lib/chat_app/search/fts5_index.ex)
- Dev controller & route: [lib/chat_app_web/controllers/dev_controller.ex](lib/chat_app_web/controllers/dev_controller.ex), [lib/chat_app_web/router.ex](lib/chat_app_web/router.ex)

**Contact / Handoff ownership**

- If you need a hand running the demo in-person, I can prepare a small shell script that builds assets, seeds demo data, and generates the fallback HTML. Right now I stopped after improving UI and fixing the compilation error.

---

If you'd like, I can (pick one):

- add committed offline demo images and switch `demo.ex` to use them,
- add a tiny e2e smoke test (cypress or Playwright) that validates core demo flows, or
- produce a small script `scripts/start_demo.sh` that runs the full sequence used in the demo.

End of handoff.

# THREADWORKS AI — AGENT HANDOFF DOCUMENT

_Generated: 2026-05-13. For: Codex or any autonomous coding agent resuming work on this repo._

---

## PROJECT OVERVIEW

**What the system does:**
Threadworks AI is a single-page streaming AI chat console for second-hand clothing recommendations. Users chat with an AI style consultant; the system does RAG (retrieval-augmented generation) over a SQLite-backed clothing inventory sourced from eBay, Depop, and Poshmark. Recommendations are shown as product cards embedded in the chat stream.

**Core product goals:**

1. Streaming AI chat with persistent conversations (per-session, SQLite)
2. RAG pipeline: hybrid vector+FTS5 search → LLM augmented prompt → streamed JSON card extraction
3. ETL pipeline scraping 3 sources on cron, deduplicating, embedding via OpenAI, indexing in sqlite-vec and FTS5
4. Multi-theme UI (4 themes: editorial, swiss, mid-century, techno-brutalist) with per-conversation settings

**Current maturity:** Feature-complete through Phase 4 (RAG streaming cards render inline). Phase 5 (saved items, `/saved` page, user preferences) is **partially implemented** (ProductCard component done; save/unsave events, SavedLive, preferences UI not yet built).

**High-level architecture:**

```
Browser ←→ Phoenix LiveView (ChatLive) ←→ OpenAI SSE stream
                        ↓ RAG path
              ChatApp.AI.StyleAdvisor
                ↓ HybridEngine
         VectorStore (sqlite-vec) + FTS5Index (SQLite FTS5)
                ↑ populated by
         Oban EmbedWorker + ScrapeWorker (eBay/Depop/Poshmark ETL)
```

---

## CURRENT STATUS

### Completed

- All of Phase 0 (schema, migrations, vector codec, auth tables)
- Phase 1 ETL: normalizer, deduplicator, eBay/Depop/Poshmark adapters, ScrapeWorker (Oban), EmbedWorker (Oban)
- Phase 2 search: VectorStore (sqlite-vec KNN), FTS5Index (BM25), QueryProcessor, HybridEngine (RRF fusion), filter opts
- Phase 3 chat: ChatLive full state machine, streaming, persistence, settings, sidebar, themes
- Phase 4 RAG: StyleAdvisor augment, QueryUnderstander evaluate, ResponseParser streaming JSON extraction, card rendering inline in assistant bubbles, ProductCard component
- Auth (phx.gen.auth): users, sessions, user settings live view
- Sprint hardening 11–16: SSE buffer fix, O(N) upsert, rate limiting (Hammer), structured logging, Markdown XSS prevention, retry/backoff, Oban cron setup

### Partially Completed (Phase 5 — SP-05-04b is the blocker)

- `ChatAppWeb.ProductCard` (`lib/chat_app_web/components/product_card_component.ex`) — HEEx function component: **done** (SP-05-01)
- `ChatAppWeb.Components.ProductCard` (`lib/chat_app_web/components/product_card.ex`) — legacy raw-HTML wrapper kept for test compatibility: **done**
- `:pending_cards` streaming collection in `ChatLive` — **partially done**: populated during stream, attached to assistant message on `:stream_done`, but **not persisted to DB** (cards are lost on reload)
- `handle_event("refresh_listings")` in `ChatLive` — **not implemented**
- `SavedLive` (`/saved` route) — **not started**
- `save_item/unsave_item` event handlers in `ChatLive` — **not implemented**
- `Clothing.save_item/3`, `Clothing.unsave_item/2`, `Clothing.list_saved_items/1`, `Clothing.list_saved_item_ids/1`, `Clothing.get_price_delta/1` — **not implemented**
- User preferences UI in `UserLive.Settings` — **not started**
- Sidebar "Refresh listings" button and "Last scraped" label — **not implemented**

### Broken / Not Working

- `ChatAppWeb.ProductCard.@source_labels` only maps `"amazon"` and `"ebay"`/`"store"` — **missing `"depop"` and `"poshmark"`**. This means `source_label/1` returns the raw atom string for Depop/Poshmark items in `product_card_component.ex`. The `StyleAdvisor`'s `@source_labels` (correct: has depop/poshmark) is a separate map and is not shared.
- `product_card_component.ex` calls `@item.condition_normalized || @item.condition` but `ClothingItem` schema only has `:condition_normalized` (`:condition` is a separate string field that may be nil). `condition_label/1` in the HEEx component does `String.to_existing_atom` which will raise `ArgumentError` if condition_normalized is an unexpected atom string value not previously interned.
- No card persistence: `:pending_cards` are attached in-memory to the last assistant message on `:stream_done`, but the message row in SQLite only stores text content. Cards do not survive page reload.

### Untested / Missing Test Coverage

- SP-05-04b tests (all): card attach integration, refresh_listings enqueue, stream-persist
- SavedLive page (not built yet)
- Preferences form persistence
- Card persistence after page reload (currently broken by design — no schema support)

### Blocked

- SP-05-03 (SavedLive page) depends on `Clothing.save_item/3` etc. — no schema for `saved_items` exists... **wait, it does**: migration `20260506195935_create_saved_items.exs` is present. The Elixir context functions just haven't been written.
- SP-05-05 (preferences) depends on `user_preferences` table — migration `20260506224125_create_user_preferences.exs` is present. The context functions haven't been written.

---

## REPOSITORY MAP

```
/Users/agard/NJIT/IS322/Final/
  chat_app/                      ← Elixir/Phoenix application root (cd here for all mix commands)
    lib/
      chat_app/
        ai/
          embedder.ex            ← OpenAI text-embedding-3-small, 512-dim, L2-normalized
          query_understander.ex  ← Decides recommend vs. clarify based on RRF score threshold
          response_parser.ex     ← Streaming JSON extraction; brace-counting parser for {"cards":[...]}
          style_advisor.ex       ← RAG prompt builder; calls HybridEngine, injects items into system prompt
          style_advisor_behaviour.ex ← Behaviour for Mox-based testing
          vector_codec.ex        ← Encodes/decodes float32 list ↔ binary (little-endian IEEE 754)
        accounts/                ← phx.gen.auth generated; User, UserToken, Scope, UserNotifier
        clothing/
          item.ex                ← ClothingItem Ecto schema; fields: title,brand,size,condition,price,url,image_url,description,embedding,source,source_id,condition_normalized,last_scraped_at,rrf_score(virtual)
          price_history.ex       ← PriceHistory schema (item_id FK, price Decimal)
        conversations/
          conversation.ex        ← Conversation schema (session_id, title, model, system_prompt, temperature)
          message.ex             ← Message schema (conversation_id FK, role atom, content string)
          usage_record.ex        ← UsageRecord schema (prompt_tokens, completion_tokens, total_tokens, estimated_cost_cents)
        conversations.ex         ← Boundary: get_or_create_active, append_message, update_assistant_message, record_usage, usage_for_conversation, delete_conversation, etc.
        clothing.ex              ← Boundary: list_items, get_item, get_item!, create_item, search_hybrid (delegates to HybridEngine), search_items (legacy ILIKE)
        search/
          fts5_index.ex          ← FTS5 upsert (delete-then-insert pattern with clothing_fts_meta tracking) + BM25 search
          hybrid_engine.ex       ← RRF fusion of VectorStore (k=50) + FTS5Index (k=50); parallel Task.Supervisor; filter opts: source/max_price/size
          hybrid_engine_behaviour.ex ← Behaviour for Mox
          query_processor.ex     ← FTS5 query escaping
          vector_store.ex        ← sqlite-vec KNN search using MATCH syntax (pinned to 0.1.5 native)
        etl/
          deduplicator.ex        ← Upsert by (source, source_id) with price_history insertion in transaction
          embedder.ex            ← Thin wrapper over AI.Embedder for batch embedding
          fts5_index.ex          ← Shim: defdelegate to Search.FTS5Index (historical alias)
          normalizer.ex          ← Normalizes raw scraper output to ClothingItem attrs
          sources/
            ebay.ex              ← eBay Browse API v1; OAuth2 token via TokenCache GenServer
            ebay/token_cache.ex  ← GenServer caching eBay OAuth token with expiry
            depop.ex             ← Depop API adapter
            poshmark.ex          ← Poshmark scraper adapter
          workers/
            embed_worker.ex      ← Oban worker (:embedder queue, max_attempts: 3); calls Embedder.embed_batch, VectorCodec.encode, clothing_vec INSERT, FTS5Index.upsert
            scrape_worker.ex     ← Oban worker (:scraper queue); triggers ETL per query
        openai.ex                ← Req-based SSE streaming client; retry/backoff; sends {:stream_token,_}, :stream_done, {:stream_error,_}, {:stream_usage,_}, {:stream_retrying,_} to lv_pid
        openai/
          e2e_stub.ex            ← Deterministic stub for Wallaby E2E tests (sends tokens synchronously)
          sse.ex                 ← SSE chunk parser; accumulates partial lines via req.private[:sse_buf]
          stub.ex                ← Unit-test stub; sends empty token, leaves :stream_done for test to send
        application.ex           ← Supervision tree: Repo, Telemetry, PubSub, TaskSupervisor, Oban, Ebay.TokenCache, Endpoint
        repo.ex                  ← Ecto.Repo using Ecto.Adapters.SQLite3
        markdown.ex              ← HTML-escapes input before Earmark parse (XSS prevention)
        chat.ex                  ← Legacy (may be near-dead); upsert_assistant_message pure fn
        ecto/decimal_string.ex   ← Custom Ecto type
      chat_app_web/
        live/
          chat_live.ex           ← Main LiveView; 1697 lines; ALL chat state machine logic here
          sidebar_component.ex   ← Stateless function component; conversation list with switch/rename/delete
          user_live/             ← Auth screens (registration, login, confirmation, settings)
        components/
          product_card.ex        ← Legacy wrapper (ChatAppWeb.Components.ProductCard); returns {:safe, iolist}
          product_card_component.ex ← HEEx function component (ChatAppWeb.ProductCard); used in ChatLive
          core_components.ex     ← Icon component + flash; @moduledoc mentions daisyUI but daisyUI NOT installed
          layouts.ex             ← Root layout with theme script
        controllers/
          dev_controller.ex      ← /dev/product_card for visual testing of ProductCard
        router.ex                ← Single route: live "/" ChatLive; auth routes; no /saved yet
    priv/
      repo/
        migrations/              ← 17 migrations total; all run via `mix ecto.migrate`
        chat_app_dev.db          ← Local SQLite dev DB (committed? probably not tracked)
        chat_app_test.db         ← Test DB
    test/
      unit/                      ← Pure unit tests; no DB
      integration/               ← DB-backed; use Sandbox
      e2e/                       ← Wallaby browser tests + sprint E2E acceptance tests
      chat_app/                  ← Module-level tests (DB-backed)
      fixtures/embeddings.exs    ← Precomputed 512-dim vectors for offline tests
    config/
      config.exs                 ← Oban cron (ScrapeWorker every 2h), scrape_queries, model="gpt-4o"
      runtime.exs                ← Loads .env via Dotenvy (dev only); requires OPENAI_API_KEY
      test.exs                   ← openai_module: ChatApp.OpenAI.Stub; disable_rate_limit: true; sandbox: manual
    AGENTS.md                    ← Phoenix v1.8 and Elixir coding guidelines (READ THIS FIRST)
    ARCHITECTURE.md              ← High-level architecture doc (may be slightly stale)
  docs/
    sprints/
      complete/                  ← All past sprint specs
      planned/
        SP-05-03-saved-page.md
        SP-05-04a-chat-save-unsave.md
        SP-05-04b-chat-stream-refresh.md ← NEXT SPRINT
        SP-05-05-preferences.md
    phases/
      phase-5-ui.md              ← Complete Phase 5 spec; the authoritative source for what to build
  .github/workflows/ci.yml       ← GitHub Actions; runs: compile --warnings-as-errors, test.setup --exclude real_api --exclude e2e, npm test
```

---

## ARCHITECTURE + DATA FLOW

### Chat / RAG Request Lifecycle

```
User types → "send_message" event
  → append_message(:user) to SQLite
  → send(self(), {:do_rag, text})
  → handle_info({:do_rag, text}):
      StyleAdvisor.augment(text, conversation_tokens: N)
        → HybridEngine.search(text)
            → Embedder.embed(text)  [OpenAI API call]
            → VectorStore.search(query_vec, 50)  [sqlite-vec MATCH]
            → FTS5Index.search(processed_query, 50)  [FTS5 BM25]
            → RRF fuse ranks → filter by source/price/size → Repo.all
        → builds augmented system prompt with item list
      QueryUnderstander.evaluate(items)
        → {:clarify, question}  [< 2 items with rrf_score >= 0.015]
        → {:recommend, items}
  → {:recommend}: start_streaming(augmented_prompt, socket)
      → Task.Supervisor.start_child → OpenAI.stream(messages, pid, opts)
          → SSE chunks → {:stream_token, token} → handle_info
            → ResponseParser.parse(token, buffer)
              → extracts {"cards":[...]} JSON when complete
              → Clothing.get_item(card.item_id) → appends to :pending_cards
          → :stream_done → handle_info
            → attaches :pending_cards to last assistant message struct
            → Conversations.update_assistant_message (text only, no cards)
```

### Persist Pattern During Streaming

- Every token: schedule_persist_timer (250ms debounce) + bump_persist_token_count
- Every 10 tokens: maybe_persist_by_token_threshold → Conversations.update_assistant_message
- On :stream_done: final Conversations.update_assistant_message
- Cards are attached in-memory to the message struct but NOT written to DB (known gap)

### ETL Pipeline

```
Oban ScrapeWorker (every 2h cron, queues: scraper: 3)
  → Sources.Ebay/Depop/Poshmark fetch_items(query)
  → ETL.Normalizer.normalize(raw_items)
  → ETL.Deduplicator.upsert_all(items)
    → clothing_items upsert by (source, source_id)
    → price_history INSERT per upsert
  → enqueue EmbedWorker jobs (queues: embedder: 5)

Oban EmbedWorker
  → Repo.all items by item_ids
  → ETL.Embedder.embed_batch(texts)  [OpenAI API]
  → VectorCodec.encode(embedding) → clothing_items.embedding UPDATE
  → DELETE FROM clothing_vec WHERE rowid=id
  → INSERT INTO clothing_vec(rowid, embedding) VALUES (id, blob)
  → FTS5Index.upsert(item_id)
    → DELETE old FTS row, INSERT new row, UPDATE clothing_fts_meta
```

### Session / Auth

- Sessions are anonymous by default: `session_id` derived from CSRF token hash or random bytes
- Full phx.gen.auth installed: users can register/login, but ChatLive at `/` is NOT behind auth guard
- `/users/settings` requires auth; `/` works with or without auth
- `current_scope` assign is populated by `:fetch_current_scope_for_user` plug (always runs)
- `@current_scope.user` may be nil for unauthenticated users

### DB Interactions

- SQLite via Ecto.Adapters.SQLite3 (ecto_sqlite3 ~> 0.13)
- sqlite-vec 0.1.0 (native 0.1.5) — loaded as NIF extension
- FTS5 built into SQLite
- `clothing_vec` — vec0 virtual table; does NOT support OR REPLACE → must DELETE then INSERT
- `clothing_fts` — FTS5 external content table backed by `clothing_items`; requires delete command before re-insert; `clothing_fts_meta` tracks last indexed title
- Sandbox mode: `:manual` (all tests must call `Ecto.Adapters.SQL.Sandbox.checkout/1`)
- Oban uses `prefix: false` (no schema prefix) and `notifier: Oban.Notifiers.PG`

### State Management in ChatLive

Key assigns:

- `messages` — list of `%{id: integer|nil, role: :user|:assistant, content: string, cards: [...]}` (cards only on completed assistant messages)
- `is_sending` — boolean gate; prevents double-send
- `stream_buffer` — accumulates raw LLM output token-by-token
- `stream_task_pid` — Task.Supervisor child pid; killed in terminate/2 and cancel_stream
- `assistant_message_id` — DB row ID for in-flight assistant message
- `pending_cards` — `[%{item: %ClothingItem{}, reason: string}]` accumulated from ResponseParser
- `rag_status` — `:idle | :searching | :streaming`
- `response_parser_buffer` — partial JSON accumulation for ResponseParser

---

## IMPORTANT DECISIONS

### SQLite instead of Postgres

- Chosen for zero-dependency local dev and deployment simplicity (NJIT project context)
- Implication: no concurrent write safety beyond SQLite's WAL mode; busy-retry logic in `Conversations.insert_with_busy_retry/2`

### sqlite-vec pinned to `== 0.1.0`

- Native lib 0.1.5 confirmed working with MATCH syntax
- **Do not upgrade** without re-testing MATCH query syntax — API changed between versions
- `OR REPLACE` does NOT work on vec0 tables; must DELETE then INSERT in transaction

### FTS5 external content table pattern

- `clothing_fts` uses `content='clothing_items'` but FTS5 doesn't auto-update on content table changes
- Requires manual delete-then-insert via `FTS5Index.upsert/1`
- `clothing_fts_meta` table tracks last indexed title so delete command can supply exact old value
- **Do NOT skip the meta lookup** — without it, old tokens accumulate in the index

### Stub architecture for OpenAI

- `ChatApp.OpenAI.Stub` — configured globally in test.exs; unit tests control token/done messages manually
- `ChatApp.OpenAI.E2EStub` — used by Wallaby `FeatureCase`; switches `:openai_module` at runtime per test
- **E2E tests MUST use Bypass or E2EStub for OpenAI embeddings** — see project memory `feedback_e2e_bypass_pattern.md`

### `@source_labels` in StyleAdvisor vs ProductCard

- `StyleAdvisor.@source_labels` = `%{"ebay" => "eBay", "depop" => "Depop", "poshmark" => "Poshmark"}` ← **correct**
- `ChatAppWeb.ProductCard.@source_labels` = `%{"amazon" => "Amazon", "ebay" => "eBay", "store" => "Store"}` ← **wrong/stale**
- See project memory `project_source_labels_risk.md` — adding new sources without updating StyleAdvisor's `@source_labels` crashes `augment/2` via `Map.fetch!/2`

### ChatLive uses `use Phoenix.LiveView` directly (not `ChatAppWeb, :live_view`)

- Reason: needs `container: {:div, style: "min-height: 100%;"}` for viewport filling
- Implication: must manually import/use Gettext, VerifiedRoutes, etc. — they are NOT auto-imported

### Dual ProductCard modules

- `ChatAppWeb.ProductCard` (product_card_component.ex) — HEEx function component; used in ChatLive render
- `ChatAppWeb.Components.ProductCard` (product_card.ex) — legacy raw iolist renderer; kept for test compatibility
- **ChatLive uses `ChatAppWeb.ProductCard.product_card/1`** (the HEEx one)

---

## WORK IN PROGRESS

### SP-05-04b — ChatLive pending-card streaming attach & refresh listings

**Current state:** Spec written at `docs/sprints/planned/SP-05-04b-chat-stream-refresh.md`

- `:pending_cards` collection is populated and attached in ChatLive already (done in SP-04-05)
- Missing: card persistence to DB (needs schema change or JSON column on messages)
- Missing: `handle_event("refresh_listings", _, socket)` — enqueue ScrapeWorker per source

**Remaining tasks:**

1. Decide card persistence strategy: either (a) add a `cards_json` text column to `messages` table via new migration and serialize/deserialize on write/read, or (b) accept cards as ephemeral (current behavior). Phase 5 spec requires persistence.
2. Implement `handle_event("refresh_listings", _, socket)` in `ChatLive`:
   ```elixir
   queries = Application.get_env(:chat_app, :scrape_queries, [])
   Enum.each(queries, fn q -> Oban.insert!(ChatApp.ETL.Workers.ScrapeWorker.new(%{"queries" => [q]})) end)
   {:noreply, put_flash(socket, :info, "Refreshing listings in the background")}
   ```
3. Add Oban.Testing assertions in tests (use `Oban.Testing.with_testing_mode(:inline, fn -> ... end)`)

**Files to modify:**

- `lib/chat_app_web/live/chat_live.ex`
- `priv/repo/migrations/` (new migration for cards_json if persisting)
- `lib/chat_app/conversations.ex` (if persisting cards)
- `test/unit/live/chat_live_rag_unit_test.exs`
- `test/integration/live/chat_live_rag_test.exs`
- `test/e2e/sp_04_04_chatlive_rag_e2e_test.exs`

### SP-05-03 — SavedLive page (/saved)

**Current state:** Schema ready (migrations `_create_saved_items.exs` exists). Nothing else built.
**Files to create:** `lib/chat_app_web/live/saved_live.ex`, add route to `router.ex`
**Files to modify:** `lib/chat_app/clothing.ex` (add save_item, unsave_item, list_saved_items, list_saved_item_ids, get_price_delta)

### SP-05-04a — Chat save/unsave events

**Current state:** `save_item`/`unsave_item` phx-click attributes on ProductCard buttons but no handlers in ChatLive
**Files to modify:** `lib/chat_app_web/live/chat_live.ex` (add handle_event for save_item, unsave_item), `lib/chat_app/clothing.ex`

### SP-05-05 — User preferences

**Current state:** Schema ready (`user_preferences` migration exists). No context functions or UI.
**Files to create/modify:** UserLive.Settings (add preferences section), `lib/chat_app/accounts.ex` (save_preferences)

---

## KNOWN ISSUES

### High Risk

- **`ChatAppWeb.ProductCard.@source_labels` missing depop/poshmark:** `source_label("depop")` returns `"depop"` (raw string). Not a crash but wrong display.
- **`condition_label/1` in product_card_component.ex uses `String.to_existing_atom/1`:** Will raise `ArgumentError` if `condition_normalized` value was never interned as an atom in the runtime. Known atoms are `new`, `used`, `refurbished`, `unknown` — safe for current data but fragile.
- **Card data lost on reload:** `:pending_cards` attach to in-memory message struct but not persisted. Cards disappear on page reload.
- **No saved_items context functions:** `ChatAppWeb.ProductCard` renders save/unsave buttons but clicking them will hit a `handle_event` clause that doesn't exist → LiveView will log "unknown event" and ignore silently (not a crash but feature is dead).

### Medium Risk

- **`ensure_usage_foreign_rows/2` in Conversations:** Creates orphan Conversation/Message rows with session_id `"usage-{id}"` if FK refs are missing. This is a defensive hack for CI test isolation; can produce ghost conversations.
- **`derive_session_id/2` fallback chain:** Includes `Code.ensure_loaded?(Mix) and Mix.env() == :test` which calls Mix at runtime. This is gated but still wrong in principle — Mix should never be called at runtime in a release. In dev/test it's fine.
- **Oban `prefix: false`:** Works for single-DB SQLite but means Oban tables are at the root schema. Don't change this.
- **Rate limiter uses Hammer ETS backend:** 20 messages per 60s per session+socket_id combo. Rate limit key includes `socket.id || :erlang.phash2(self())` — can accumulate many keys in ETS under high load.

### Low Risk

- **`fix_conversations.exs` and `fix_conversations.py` in repo root:** Scripts from an earlier debugging session. Not referenced by anything. Can be deleted.
- **`erl_crash.dump` in chat_app/:** Should be gitignored; exists locally.
- **`test_output.txt` in chat_app/:** Debug artifact. Should be gitignored.
- **`CoreComponents` @moduledoc mentions daisyUI:** daisyUI is NOT installed. The module itself is fine; just the doc is wrong.
- **`Clothing.search_items/1`:** Legacy ILIKE search. Not used by RAG pipeline. Can coexist but confusing naming.
- **`ChatApp.Chat` module:** Near-dead module, `upsert_assistant_message/2` is the main function; the logic was inlined into ChatLive. Not actively harmful.

---

## TESTING STATUS

### What is Covered

- Full unit coverage of: ResponseParser, QueryUnderstander, StyleAdvisor (via Mox), HybridEngine (via Mox), VectorStore, FTS5Index, Embedder, OpenAI (Bypass), SSE parser, Markdown
- Integration: HybridEngine with real DB, FTS5Index with real DB, VectorStore with real DB, ChatLive full event flow (mock OpenAI)
- E2E (Wallaby): ChatLive layout, hero, composer, streaming, multi-turn, themes, RAG pipeline (with Bypass for embeddings)
- Migration tests: each schema migration has a test asserting table/column existence
- Sprint regression tests: sprint_11 through sprint_20 have dedicated test files asserting hardening invariants

### Missing Coverage

- Card persistence after reload (feature not built)
- `refresh_listings` event handler (not built)
- SavedLive page (not built)
- Save/unsave event handlers (not built)
- Preferences form (not built)
- EmbedWorker failure paths (partial)

### Unreliable Tests

- Wallaby E2E tests are the most fragile (browser timing). CI excludes them (`--exclude e2e`).
- `@tag :real_api` tests hit live OpenAI API; excluded from CI.
- Test DB isolation: all tests require `Sandbox.checkout(ChatApp.Repo)`. Tests using async: true must use `Sandbox.allow/3` for spawned processes.

### Critical Regression Risks

- Modifying `HybridEngine.search/2` — any change to RRF scoring breaks `QueryUnderstander.evaluate/1` thresholds
- Modifying `StyleAdvisor.@source_labels` — must include all 3 sources or `Map.fetch!` crashes on augment
- Modifying `VectorStore.search/2` — MATCH syntax is fragile; sqlite-vec 0.1.0 only
- Modifying `Conversations.insert_with_busy_retry/2` — removes SQLite busy retry protection
- Adding new scraper source — must update `StyleAdvisor.@source_labels` AND `ChatAppWeb.ProductCard.@source_labels`

---

## ENVIRONMENT + OPERATIONS

### Required Env Vars

```
OPENAI_API_KEY=sk-...          # Required at runtime (fatal if missing in dev/prod)
EBAY_APP_ID=...                # Required for eBay scraping (optional; scraper returns {:error, :missing_credentials} if absent)
EBAY_CERT_ID=...               # Required for eBay OAuth
BASIC_AUTH_USER=               # Optional; enables HTTP basic auth if both set
BASIC_AUTH_PASSWORD=           # Optional
OPENAI_EMBEDDINGS_URL=         # Optional; defaults to https://api.openai.com/v1/embeddings (override for test stub)
```

CI sets `OPENAI_API_KEY=sk-test-stub-ci` (fake value — OK because tests use Stub/Bypass).

### Local Setup

```bash
cd chat_app
cp .env.example .env           # Fill in OPENAI_API_KEY at minimum
mix setup                      # deps.get + ecto.create + ecto.migrate + assets
iex -S mix phx.server          # Start dev server
```

### Test

```bash
mix test.setup                 # ecto.create + ecto.migrate + test
mix test --exclude real_api --exclude e2e   # CI-equivalent
mix test test/unit/ai/response_parser_test.exs   # Single file
```

### Pre-commit

```bash
mix precommit   # compile --warnings-as-errors + deps.unlock --unused + format + test + npm test
```

### Migrations

- All migrations are in `priv/repo/migrations/`
- Run `mix ecto.migrate` to apply
- SQLite WAL mode enabled by default in ecto_sqlite3

### Oban Cron

- ScrapeWorker fires every 2 hours: `"0 */2 * * *"`
- Queries: `["vintage levi", "y2k denim", "silk slip dress", "90s windbreaker", "cashmere sweater"]`
- EmbedWorker is enqueued by ScrapeWorker after upsert; no separate cron

### External Services

- OpenAI API: `/v1/chat/completions` (streaming) + `/v1/embeddings` (text-embedding-3-small)
- eBay Browse API v1 (OAuth2 client credentials)
- Depop API (no auth configured in current adapter)
- Poshmark (scraper, no API key)

---

## NEXT RECOMMENDED ACTIONS

### Immediate Next Task: SP-05-04b

This is the highest-priority incomplete sprint. The spec is at `docs/sprints/planned/SP-05-04b-chat-stream-refresh.md`.

**Exact execution order:**

1. **Fix `ChatAppWeb.ProductCard.@source_labels`** first (2 min, zero risk):

   ```elixir
   # lib/chat_app_web/components/product_card_component.ex
   @source_labels %{
     "ebay" => "eBay",
     "depop" => "Depop",
     "poshmark" => "Poshmark"
   }
   ```

2. **Decide card persistence approach.** Recommended: add `cards_json TEXT` column to `messages` via new migration. Serialize with `Jason.encode!/1`, deserialize on `list_messages/1`. This is a targeted change. Alternative: defer persistence (mark cards as ephemeral) — simpler but violates phase 5 spec.

3. **If persisting cards:** Create migration `20260513000000_add_cards_json_to_messages.exs`, update `Conversations.append_message/3` and `update_assistant_message/2`, deserialize in `ChatLive.mount` when loading messages.

4. **Implement `handle_event("refresh_listings", _, socket)` in `ChatLive`:**
   - Read `Application.get_env(:chat_app, :scrape_queries, [])`
   - Enqueue one `ScrapeWorker` job per query via `Oban.insert/1`
   - Return `put_flash(socket, :info, "Refreshing listings in the background")`
   - Handle empty config gracefully

5. **Add sidebar "Refresh listings" button** in `sidebar_component.ex` (phx-click="refresh_listings")

6. **Write tests** per SP-05-04b spec: unit (card attach, refresh enqueue), integration (full ChatLive flow), E2E (stream → cards persist)

7. **Run `mix precommit`** before committing.

### Quick Wins (< 30 min each)

- Fix `@source_labels` in `product_card_component.ex` (2 min)
- Delete `fix_conversations.exs`, `fix_conversations.py`, `test_output.txt`, `erl_crash.dump` from repo
- Fix `CoreComponents` @moduledoc to remove daisyUI reference

### High-Risk Areas (investigate before touching)

- `VectorStore.search/2` — sqlite-vec MATCH syntax; do not change query format
- `FTS5Index.upsert/1` — delete-then-insert pattern with meta table; do not simplify
- `ChatLive` streaming state machine — many interlocking handles; test every code path

### What NOT to Touch Yet

- `ChatApp.OpenAI.Stub` and `ChatApp.OpenAI.E2EStub` — rely on exact message shapes; any change breaks many tests
- `ChatApp.AI.VectorCodec` — binary encoding format; changing it invalidates all stored embeddings
- `Oban` configuration (`prefix: false`, `notifier: PG`) — works with SQLite; changing breaks CI

### Where More Investigation Is Needed

- `saved_items` schema: check `20260506195935_create_saved_items.exs` for exact column names before writing context functions
- `user_preferences` schema: check `20260506224125_create_user_preferences.exs` for exact column structure (sizes, brands, budget_min, budget_max, style_keywords)
- Auth scoping for SavedLive: must go in `live_session :require_authenticated_user` block in `router.ex`

---

## CODE QUALITY ASSESSMENT

### Strongest Parts

- `ChatApp.OpenAI` — clean retry/backoff, no process dict state, good logging
- `ChatApp.Search.HybridEngine` — parallel tasks with timeout, clean RRF fusion
- `ChatApp.AI.ResponseParser` — robust brace-counting parser handles LLM prose with `{word}` before JSON block
- `ChatApp.Conversations` — well-bounded context with SQLite busy retry
- Test infrastructure — layered unit/integration/e2e with distinct stubs per layer; fixtures file for embeddings

### Weakest Parts

- `ChatAppWeb.ChatLive` — 1697 lines, everything in one file; stream state machine + RAG + render + all event handlers + all private helpers; no decomposition into LiveComponents despite AGENTS.md warning against LiveComponents
- `ChatAppWeb.Components.ProductCard` (product_card.ex) — raw iolist HTML generation; uses `Phoenix.HTML.safe_to_string(html_escape(...))` manually; should have been refactored to pure HEEx when product_card_component.ex was created
- Dual ProductCard modules — confusing; `ChatAppWeb.Components.ProductCard.render/1` is the legacy one; `ChatAppWeb.ProductCard.product_card/1` is the current one; the legacy one should eventually be deleted once test deps are cleaned up

### Coupling Issues

- `ChatLive` directly calls `StyleAdvisor.augment/2` synchronously in `handle_info({:do_rag, ...})` — this blocks the LiveView process during the OpenAI embeddings call (though it's fast)
- `StyleAdvisor` hardcodes `@source_labels` independently from `ProductCard` — these must stay in sync manually

### Maintainability Risks

- No LiveView streams used for message list — messages stored as a plain list in assigns; grows unbounded with long conversations; could cause memory pressure at scale
- Card persistence not designed into schema upfront; retrofitting requires migration + serialization

---

## CONTEXT THAT IS EASY TO LOSE

- **`FTS5Index.upsert/1` lives in TWO places:** `ChatApp.Search.FTS5Index` (canonical) and `ChatApp.ETL.FTS5Index` (shim). `EmbedWorker` calls the ETL alias. Do not delete the shim without updating EmbedWorker.

- **`ChatApp.OpenAI.Stub` sends `{:stream_token, ""}` and then sleeps 100ms.** It does NOT send `:stream_done`. Tests must send `:stream_done` themselves. `E2EStub` DOES send `:stream_done`. Mixing them up causes flaky tests.

- **`rrf_score` on `ClothingItem` is a virtual field.** It's set by `HybridEngine` with `%{item | rrf_score: score}` pattern. Never stored in DB. `QueryUnderstander.evaluate/1` depends on it being set — passing raw DB items (without rrf_score) will evaluate 0.0 and always trigger :clarify.

- **`QueryUnderstander` threshold `@min_rrf_score 0.015` with `@min_results 2`:** With RRF k=60 and a list of 10 items, typical scores range 0.008–0.016. This threshold is empirically tuned — changing it changes the :clarify/:recommend ratio meaningfully.

- **`StyleAdvisor.augment/2` uses `Map.fetch!(@source_labels, ...)` not `Map.get`:** This WILL crash with a KeyError if a clothing item has a source not in `@source_labels`. The current map covers `"ebay"`, `"depop"`, `"poshmark"`. Any new source must be added here first.

- **`ChatLive.mount/3` calls `Conversations.get_or_create_active(session_id)` only when `connected?(socket)`.** On static render (not connected), messages is `[]` and conversation_id is nil. This is intentional — avoids DB calls on the initial static HTTP render.

- **`derive_session_id/2`** priority order: socket assigns > connect_params > session map > test env > CSRF hash > random. In test, returns `"test-session"` when `Mix.env() == :test` — this means all tests share the same session_id, which is intentional for test isolation.

- **`Conversations.settings_model_or_default/1`** defaults to `"gpt-4o-mini"` (not `"gpt-4o"`). The `config.exs` sets global model to `"gpt-4o"` but per-conversation default is mini. New conversations start with gpt-4o-mini unless the user changes the settings.

- **`ChatLive` calls `style_advisor_module()` via `Application.get_env(:chat_app, :style_advisor_module, ChatApp.AI.StyleAdvisor)`** — allows Mox override in tests. Similarly for `:openai_module` and `:hybrid_engine_module`. These are the three dependency injection points.

- **The `PromptOnEvent` JS hook** (`id="prompt-bridge"`) at the top of ChatLive render is used to push `prompt_rename` events to the client for the rename-conversation JS prompt. It's invisible (`class="hidden"`). Do not remove it.

- **Product card save/unsave buttons** in `product_card_component.ex` have `phx-click="save_item"` and `phx-click="unsave_item"` but ChatLive has no handlers for these events yet. Clicking them will log "unknown event" silently.

---

## FINAL ADVICE TO CODEX

1. **Read `chat_app/AGENTS.md` in full before writing any code.** It contains Phoenix 1.8 + Elixir + LiveView + CSS constraints that override all defaults. Key violations that will cause build failures: using `@apply` in CSS, using deprecated `live_redirect`, calling `<.flash_group>` outside layouts, using `daisyUI`.

2. **Run `mix precommit` before every commit.** It runs `compile --warnings-as-errors` — stale modules and unused variables fail the build.

3. **Test file organization is strict:** unit tests go in `test/unit/`, integration in `test/integration/`, E2E in `test/e2e/`, sprint acceptance in their own sprint file. Match the existing pattern.

4. **All tests that touch the DB must call `Ecto.Adapters.SQL.Sandbox.checkout(ChatApp.Repo)`** — sandbox is `:manual`. Use the existing test support modules (look at existing passing tests for patterns).

5. **Never use `Process.sleep/1` in tests** — use message assertions with `assert_receive`.

6. **The `@source_labels` mismatch between StyleAdvisor and ProductCard is a live bug.** Fix it early in any session before it causes confusion.

7. **Card persistence is the key architectural decision for Phase 5.** Recommend a `cards_json` TEXT column on `messages` with Jason serialization — it's the simplest approach that satisfies the reload requirement without a separate join table.

8. **When writing SavedLive:** it must go inside the `live_session :require_authenticated_user` block in `router.ex`. Access user as `@current_scope.user` (never `@current_user`). See AGENTS.md auth section.

9. **Oban testing:** Use `Oban.Testing` module. In test.exs, Oban is configured with `testing: :inline` or similar — check `config/test.exs` before writing Oban assertions. The spec recommends `Oban.Testing.with_testing_mode(:inline, fn -> ... end)`.

10. **sqlite-vec is pinned and fragile.** Do not touch `VectorStore.search/2` query format or the `mix.exs` version constraint.
