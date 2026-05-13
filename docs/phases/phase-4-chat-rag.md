---
status: in_progress
last_updated: 2026-05-12
phase: 4
sub_phase: 4
slug: chat-rag
complexity: M
progress: 4/5 sprints complete (SP-04-01: ✓, SP-04-02: ✓, SP-04-03: ✓, SP-04-04: ✓)
---

# Phase 4 — Chat RAG Integration

**Goal:** Retrieve relevant items before each chat completion, inject them into the system prompt, parse the LLM's structured card references from the streamed response, and emit them to LiveView.

---

## Deliverables

### `lib/chat_app/ai/style_advisor.ex`

**`build_prompt(base_system_prompt, items) :: String.t()`**
Pure function. No side effects. Appends an `AVAILABLE ITEMS` block to the base prompt:

```
AVAILABLE ITEMS:
[1] Vintage Levi's 501 Jeans | Size: 28x30 | Condition: good | $45.00 | eBay
[2] 90s Calvin Klein Blazer | Size: M | Condition: like_new | $78.00 | Depop
...

When recommending items, reference them by number. After your response, output a JSON block:
{"cards": [{"item_id": 1, "reason": "..."}, ...]}
Only include items you actually recommend.
```

**`augment(user_message) :: {:ok, augmented_prompt, [%ClothingItem{}]}`**
Calls `HybridEngine.search(user_message)` → if results non-empty, calls `build_prompt/2`; if empty, returns `{:ok, base_prompt, []}`.

### `lib/chat_app/ai/response_parser.ex` ✓ (SP-04-02)

**`parse(chunk :: String.t(), buffer :: String.t()) :: {[card_map()], String.t()}`**

Where `card_map()` is `%{item_id: integer(), reason: String.t()}`.

- Concatenates `chunk` to `buffer`
- Attempts `Jason.decode` on the accumulated buffer looking for `{"cards": [...]}`
- On success: extracts cards, clears matched portion from buffer, returns `{cards, remaining_buffer}`
- On failure (incomplete JSON): returns `{[], buffer <> chunk}`
- On malformed JSON (parse error after complete object): retries from next `{` in buffer, never crashes
- Caller looks up full `%ClothingItem{}` records from DB by `item_id` after receiving cards

**Status:** Complete. All 13 tests passing. Handles UTF-8, escaped quotes, multi-byte chars, spurious `{` in prefix text (with retry logic).

### `lib/chat_app/ai/query_understander.ex`

**`evaluate(items :: [%ClothingItem{}]) :: {:recommend, [%ClothingItem{}]} | {:clarify, String.t()}`**

```elixir
@min_rrf_score 0.015
@min_results 2

def evaluate(items) do
  high_relevance = Enum.filter(items, &(&1.rrf_score >= @min_rrf_score))
  if length(high_relevance) >= @min_results do
    {:recommend, items}
  else
    {:clarify, "Could you tell me more? For example: your size, budget range, and what occasion you're shopping for."}
  end
end
```

### `lib/chat_app_web/live/chat_live.ex` updates

In `handle_event("send_message", ...)`:

1. Push `{:assign, :rag_status, :searching}` to show "Searching..." indicator in UI
2. Call `StyleAdvisor.augment(user_message)` → `{:ok, augmented_prompt, items}`
3. Call `QueryUnderstander.evaluate(items)` → `{:recommend, _}` or `{:clarify, question}`
4. If `:clarify` — send clarifying question as assistant message without calling OpenAI; set `rag_status: :idle`
5. If `:recommend` — push `{:assign, :rag_status, :streaming}`; initialize `response_parser_buffer: ""` and `pending_cards: []` in socket; pass `augmented_prompt` to existing streaming pipeline
6. On each streamed chunk: call `ResponseParser.parse(chunk, socket.assigns.response_parser_buffer)` → update buffer; if cards returned, look up full items and push to `pending_cards` assign
7. On stream completion: move `pending_cards` into the message assigns for rendering; reset buffer

Token budget guard: if current conversation's total token count (from usage_records) > 3000, cap items at 8 instead of 10 in `StyleAdvisor.augment/1`.

---

## Acceptance Criteria

All criteria are unit-testable without HTTP calls or LLM invocation.

- **`build_prompt/2` unit:** `StyleAdvisor.build_prompt("base", [item1, item2, item3])` returns a string containing `"AVAILABLE ITEMS"` and exactly 3 lines matching `~r/\[\d+\] .+ \| Size:/`
- **`augment/1` empty path:** Mock `HybridEngine.search` to return `{:ok, []}`. `StyleAdvisor.augment("anything")` returns `{:ok, base_system_prompt, []}` without error.
- **`ResponseParser.parse/2` success:** `parse("{\"cards\": [{\"item_id\": 5, \"reason\": \"Great fit\"}]}", "")` returns `{[%{item_id: 5, reason: "Great fit"}], ""}`.
- **`ResponseParser.parse/2` split chunks:** Call `parse/2` three times with the card JSON split across three chunks; assert intermediate calls return `{[], partial_buffer}` and the final call returns the complete card.
- **`ResponseParser.parse/2` no JSON:** `parse("Some text with no JSON.", "")` returns `{[], "Some text with no JSON."}` — does not crash.
- **`ResponseParser.parse/2` malformed JSON:** `parse("{\"cards\": [BROKEN}", "")` returns `{[], ""}` — does not crash.
- **`QueryUnderstander.evaluate/1` clarify path:** `evaluate([])` returns `{:clarify, _}`. `evaluate([%{rrf_score: 0.008}])` returns `{:clarify, _}`.
- **`QueryUnderstander.evaluate/1` recommend path:** `evaluate([%{rrf_score: 0.02}, %{rrf_score: 0.02}])` returns `{:recommend, _}`.
- **Manual smoke test (not in CI):** Run app, send "vintage denim jacket under $60" in chat → at least one product card renders below the assistant message within 5 seconds of message send.

---

## Dependencies

- Phase 1 complete (data in DB with embeddings)
- Phase 2 complete (`HybridEngine`, `VectorStore`, `FTS5Index` working)

---

## Complexity: M

`StyleAdvisor` and `QueryUnderstander` are pure functions — easy to test. The streaming JSON accumulation in `ResponseParser` is the trickiest part: JSON can split across chunk boundaries in arbitrary ways. The `ChatLive` integration requires careful state management (buffer, pending_cards, rag_status) without breaking existing chat functionality.

---

## Risks

- **Malformed LLM JSON:** The LLM may emit `{"cards": ...}` with subtle formatting differences (trailing commas, extra whitespace). `ResponseParser` must be lenient — use `Jason.decode` inside a `try`/`rescue` or `case` with explicit error handling. Never propagate parse errors to the user.
- **Context window budget:** 10 items × ~80 tokens = ~800 tokens overhead per request. With a long conversation, this can push near limits for gpt-4o-mini (128k context, but beware cost). The token guard (cap at 8 items after 3000 conversation tokens) addresses the worst case.
- **RAG retrieval latency:** `HybridEngine.search` makes one OpenAI HTTP call (embedding) + two SQLite queries. Typical latency: 300–700ms. This happens before streaming starts, so the user sees a "Searching..." indicator and then the stream begins. Do not skip this indicator — the pause is noticeable.
- **Non-clothing messages:** If the user asks about something unrelated to clothing (e.g., "what time is it?"), `HybridEngine.search` will return low-relevance results or empty. `QueryUnderstander` will return `:clarify` or `StyleAdvisor.augment` will use the base prompt. The LLM will answer normally without product recommendations. No special-casing needed.
- **`build_prompt/2` raises on unknown source label (carry-forward from SP-04-03):** `build_prompt/2` uses `Map.fetch!(@source_labels, ...)` keyed on `"ebay"`, `"depop"`, and `"poshmark"`. If a new scraper writes a different source string to the DB without updating `@source_labels` in `style_advisor.ex`, `augment/2`'s `{:ok, results}` branch will raise `KeyError` and crash the LiveView process. The current ETL layer is closed over exactly those three sources so this cannot trigger today. **When any new scraper source is added (Phase 5+), `@source_labels` in `lib/chat_app/ai/style_advisor.ex` must be updated at the same time.**
