---
id: SP-04-02
phase: 4
slug: response-parser
status: complete
created: 2026-05-12
activated_date: 2026-05-12
completed_date: 2026-05-12
estimated_days: 1.5
depends_on: []
---

# SP-04-02 — ResponseParser: Streaming JSON Accumulation

**Goal:** Implement `ResponseParser.parse/2` with correct chunk accumulation, complete card extraction, and hardened error paths for every malformed, split, and type-unsafe JSON scenario the LLM can produce.

---

## Scope

### In

- `lib/chat_app/ai/response_parser.ex` — `parse/2` only
- `test/unit/ai/response_parser_test.exs`

### Out

- `StyleAdvisor`, `QueryUnderstander` (SP-04-01)
- LiveView integration (SP-04-04)
- HybridEngine

---

## Design Decisions Locked

**item_id coercion:** The LLM may emit `"item_id"` as either a JSON number (`5`) or a JSON string (`"5"`). `Jason.decode` preserves the JSON type. If `item_id` arrives as a binary string, downstream `Repo.get(ClothingItem, "5")` receives the wrong type and silently returns `nil`. `parse/2` **must coerce** string `item_id` values to integers. Cards where `item_id` cannot be coerced to a positive integer are silently dropped (never crash).

**Trailing text:** The spec says "clears matched portion from buffer, returns `{cards, remaining_buffer}`." Text that appears after the closing `}` of the JSON object is not part of the matched portion and is returned in `remaining_buffer` for accumulation on the next call.

**JSON extraction strategy:** Scan the accumulated buffer for the first `{` that opens a valid JSON object; do not attempt `Jason.decode` on the full buffer when non-JSON prefix text is present. Use `Jason.decode/1` (not `decode!`) inside a `case`; no exception can escape `parse/2`.

**No-JSON case:** When the buffer contains no complete JSON object, return `{[], accumulated_buffer}` — the full concatenation of prior buffer and new chunk.

**Malformed JSON case:** When the buffer contains what looks like a complete JSON object but `Jason.decode` returns an error, return `{[], ""}` — discard the buffer entirely to prevent a corrupted state from persisting across calls.

---

## Tests

### E2E — Full parse behavior

Both tests in `test/unit/ai/response_parser_test.exs`, tagged `@tag :e2e` for documentation but runnable without external I/O.

---

**E1 — Single-chunk complete parse (happy path); item_id is integer type**

```elixir
{cards, buffer} = ResponseParser.parse(~s({"cards": [{"item_id": 5, "reason": "Great fit"}]}), "")
assert length(cards) == 1
card = hd(cards)
assert card.item_id == 5
assert is_integer(card.item_id)      # not binary "5"
assert card.reason == "Great fit"
assert buffer == ""
```

Failure guarded: JSON decode failure; `item_id` returned as binary `"5"`, causing
downstream `Repo.get` to silently return nil.

---

**E2 — Trailing text after JSON block preserved in remaining_buffer**

```elixir
chunk = ~s(Here are picks: {"cards": [{"item_id": 3, "reason": "Bold"}]} enjoy!)
{cards, remaining} = ResponseParser.parse(chunk, "")
assert length(cards) == 1
assert hd(cards).item_id == 3
assert remaining == " enjoy!"
```

Failure guarded: implementation discarding post-JSON text, losing streamed content
that arrived in the same TCP chunk as the card block.

---

### Unit

All tests in `test/unit/ai/response_parser_test.exs`, describe block `"parse/2"`.

---

**U1 — Empty chunk on empty buffer returns empty result without crash**

```elixir
assert {[], ""} = ResponseParser.parse("", "")
```

Failure guarded: crash on empty strings; guard clause missing.

---

**U2 — Incomplete JSON accumulates in buffer without premature decode**

```elixir
chunk = ~s({"cards": [{"item_id": 2,)
{cards, buffer} = ResponseParser.parse(chunk, "")
assert cards == []
assert buffer == chunk
```

Failure guarded: premature `Jason.decode` on incomplete JSON raising or returning
error before the object is complete.

---

**U3 — Split mid-closing-brace: final chunk is exactly `"}]}"`**

This tests the most dangerous split: the parser must not treat `}` at inner object
level as the end of the root object.

```elixir
chunk_1 = ~s({"cards": [{"item_id": 7, "reason": "Great)
chunk_2 = ~s( fit"}]})
{cards_1, buf_1} = ResponseParser.parse(chunk_1, "")
assert cards_1 == []
assert buf_1 == chunk_1
{cards_2, buf_2} = ResponseParser.parse(chunk_2, buf_1)
assert length(cards_2) == 1
assert hd(cards_2).item_id == 7
assert hd(cards_2).reason == "Great fit"
assert buf_2 == ""
```

Failure guarded: treating the inner `}` as end-of-object, producing a malformed
decode result and discarding the card.

---

**U4 — Plain text with no JSON returns text in buffer, no crash**

```elixir
{cards, buffer} = ResponseParser.parse("Some text with no JSON.", "")
assert cards == []
assert buffer == "Some text with no JSON."
```

Failure guarded: crash when no JSON object is present in chunk.

---

**U5 — Malformed JSON after complete-looking brace discards buffer without crash**

```elixir
{cards, buffer} = ResponseParser.parse(~s({"cards": [BROKEN}), "")
assert cards == []
assert buffer == ""
```

Failure guarded: `Jason.decode!` raising instead of returning error tuple; parse
error propagating to the LiveView process.

---

**U6 — Empty cards array in valid JSON clears buffer, returns no cards**

```elixir
{cards, buffer} = ResponseParser.parse(~s({"cards": []}), "")
assert cards == []
assert buffer == ""
```

Failure guarded: crash or nil return on empty array; `[]` being treated as a decode
failure instead of a valid empty result.

---

**U7 — Non-JSON text prefix in existing buffer does not prevent extraction**

```elixir
buffer_with_prefix = "I suggest these items for you: "
chunk = ~s({"cards": [{"item_id": 2, "reason": "Casual"}]})
{cards, remaining} = ResponseParser.parse(chunk, buffer_with_prefix)
assert length(cards) == 1
assert hd(cards).item_id == 2
assert remaining == ""
```

Failure guarded: parser calling `Jason.decode` on the full concatenated string
(prefix + JSON), which fails on the leading text, and then returning `{[], ...}`
even though valid JSON is present.

---

**U8 — Multiple cards in a single chunk all extracted**

```elixir
chunk = ~s({"cards": [{"item_id": 1, "reason": "A"}, {"item_id": 2, "reason": "B"}]})
{cards, buffer} = ResponseParser.parse(chunk, "")
assert length(cards) == 2
ids = Enum.map(cards, & &1.item_id)
assert 1 in ids
assert 2 in ids
assert buffer == ""
```

Failure guarded: only first card extracted; `Enum.take(cards, 1)` somewhere in
the parsing path.

---

**M1 — String item_id from LLM is coerced to integer**

This is the production risk: GPT models sometimes emit `"item_id": "5"` (a JSON
string) instead of `"item_id": 5` (a JSON number).

```elixir
chunk = ~s({"cards": [{"item_id": "5", "reason": "Great fit"}]})
{cards, _buffer} = ResponseParser.parse(chunk, "")
assert length(cards) == 1
card = hd(cards)
assert card.item_id == 5
assert is_integer(card.item_id)
```

Failure guarded: binary `"5"` propagating to `Repo.get(ClothingItem, "5")` which
returns `nil` and silently drops the recommendation.

---

**M2 — Non-integer item_id (e.g., float or non-numeric string) drops the card**

```elixir
# Float item_id
chunk_float = ~s({"cards": [{"item_id": 5.5, "reason": "Float ID"}]})
{cards_f, _} = ResponseParser.parse(chunk_float, "")
assert cards_f == []

# Non-numeric string item_id
chunk_str = ~s({"cards": [{"item_id": "abc", "reason": "String ID"}]})
{cards_s, _} = ResponseParser.parse(chunk_str, "")
assert cards_s == []
```

Failure guarded: non-integer id propagating as-is or crashing `String.to_integer/1`
with a non-numeric value.

---

**M3 — Poisoned-buffer recovery: non-JSON prefix accumulated, then valid JSON arrives**

This is the multi-call version of U7. The prefix arrives in a prior call and sits
in the buffer; the JSON arrives in the next chunk.

```elixir
{[], buf_1} = ResponseParser.parse("I recommend the following: ", "")
assert buf_1 == "I recommend the following: "

{cards, buf_2} = ResponseParser.parse(
  ~s({"cards": [{"item_id": 9, "reason": "Warm"}]}),
  buf_1
)
assert length(cards) == 1
assert hd(cards).item_id == 9
assert buf_2 == ""
```

Failure guarded: stale text in buffer poisoning `Jason.decode` on the next
concatenation even when the new chunk contains valid JSON.

---

## Implementation Tasks

- [x] Write all tests (E1–E2, U1–U8, M1–M3) in `test/unit/ai/response_parser_test.exs` — all failing
- [x] Create `lib/chat_app/ai/response_parser.ex` with `parse/2`
  - [x] Concatenate `chunk` onto `buffer`
  - [x] Scan accumulated string for JSON object: find first `{`, attempt extract
  - [x] Use `Jason.decode/1` (not `decode!`) in a `case` — never let exceptions escape
  - [x] On successful decode of `{"cards": [...]}`:
    - [x] Coerce each `item_id` to integer: if binary, try `String.to_integer/1` wrapped in try/rescue; drop card on failure
    - [x] Drop cards where coerced `item_id` is not a positive integer
    - [x] Return `{cards, text_after_json_object}`
  - [x] On incomplete JSON (no complete object found): return `{[], accumulated}`
  - [x] On malformed JSON (complete-looking object but decode error): return `{[], ""}`
- [x] Run `mix test test/unit/ai/response_parser_test.exs` — all green

---

## Definition of Done

- [x] All 13 tests pass (E1–E2, U1–U8, M1–M3)
- [x] No code path in `parse/2` can raise an exception for any binary input — verified by passing arbitrary strings including empty, nil-like, and binary garbage
- [x] `mix test` full suite green — zero regressions
- [x] `parse/2` is the only public function in the module
