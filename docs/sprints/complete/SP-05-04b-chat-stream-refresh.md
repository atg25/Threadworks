---
id: SP-05-04b
phase: 5
status: complete
activated_date: 2026-05-13
created: 2026-05-12
completed_date: 2026-05-13
---

# SP-05-04b — ChatLive pending-card streaming attach & refresh listings

Goal
----
Attach streaming `:pending_cards` to assistant messages after stream completion, and implement `refresh_listings` to enqueue one ScrapeWorker job per configured source with user-visible flash.

Scope
-----
- In: `ChatLive` streaming attach logic, `handle_event("refresh_listings")` enqueueing Oban jobs per `:scrape_queries` config, tests using `Oban.Testing` mode.
- Out: product-card component (SP-05-01), backend saved-item persistence (SP-05-02) — blocked until those are green.

Tests
-----
Unit

- Name: chat_live_attaches_pending_cards_after_streaming_unit
  - Inputs: simulated `:pending_cards` assign then call completion handler in `ChatLive` (unit-level invocation).
  - Expected: assistant message struct receives attached cards; `:pending_cards` cleared.
  - Guards against: cards not persisted or attached to wrong message.

- Name: refresh_listings_enqueues_one_job_per_source_unit
  - Inputs: `:scrape_queries` config contains `[{"ebay"}, {"depop"}, {"poshmark"}]`.
  - Expected: handler enqueues three Oban jobs (one per source) — test using `Oban.Testing` assertions.
  - Guards against: multiple jobs per source or zero jobs.

Integration

- Name: chat_live_attaches_pending_cards_integration
  - Inputs: full `ChatLive` mount and simulated stream messages that populate `:pending_cards` followed by completion message.
  - Expected: after completion, page renders cards below the appropriate assistant message and the assistant message stored in `:messages` contains the card attachments.
  - Guards against: duplication or loss of streamed cards.

E2E

- Name: stream_attach_happy_path
  - Inputs: simulate assistant streaming event that yields two cards and completes.
  - Expected: UI progressively shows pending cards during stream and final message contains cards; reloading chat still shows cards attached to the message (persistence requirement).
  - Guards against: cards ephemeral only during live stream.

- Name: refresh_listings_shows_flash_and_enqueues_jobs (edge)
  - Inputs: user triggers `refresh_listings` click.
  - Expected: LiveView flash contains "Refreshing listings in the background" and `Oban.Job` count increases by number of sources; no UI freeze.
  - Guards against: no feedback or no jobs enqueued.

- Name: refresh_listings_handles_missing_config_gracefully (edge)
  - Inputs: `:scrape_queries` config is empty or nil.
  - Expected: handler returns with flash message "No sources configured" (or similar agreed copy) and no jobs enqueued; no crash.
  - Guards against: nil config causing runtime errors.

Implementation tasks
--------------------

- [x] Implement streaming flow integration to maintain `:pending_cards` during stream and attach to assistant message struct on completion.
- [x] Persist card attachments to the assistant message so reload shows them.
- [x] Implement `handle_event("refresh_listings", _, socket)` to read configured sources and enqueue one `ChatApp.ETL.Workers.ScrapeWorker` job per source.
- [x] Use `Oban.Testing.with_testing_mode(:inline, fn -> ... end)` in tests to assert job counts and behavior.
- [x] Add integration and E2E tests that simulate stream messages and `refresh_listings` click.

Definition of done
------------------

- [ ] All unit/integration/E2E tests for streaming and refresh pass in CI (Oban in testing mode).
- [ ] Manual check: simulate a conversation with streaming cards and verify cards persist on message after stream completion; refresh listings button shows flash and enqueues jobs.
- [ ] Defensive behavior for missing/empty scrape config documented and covered by tests.
