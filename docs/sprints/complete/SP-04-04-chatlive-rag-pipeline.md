---
id: SP-04-04
phase: 4
slug: chatlive-rag-pipeline
status: complete
created: 2026-05-12
activated_date: 2026-05-12
completed_date: 2026-05-12
estimated_days: 2
depends_on:
  - SP-04-01
  - SP-04-02
  - SP-04-03
---

# SP-04-04 — ChatLive RAG Pipeline

**Goal:** Wire `StyleAdvisor.augment/2`, `QueryUnderstander.evaluate/1`, and `ResponseParser.parse/2` into `ChatLive` with correct async state management — `rag_status`, `response_parser_buffer`, and `pending_cards` — so the UI never gets stuck and all error paths clean up safely.

**Out of scope for this sprint:** HEEx card rendering and the "Searching..." indicator. Those ship in SP-04-05 and are blocked on this sprint completing cleanly. This sprint's DoD is socket state correctness; visual output is not verified here.

---

## Scope

### In

- `lib/chat_app_web/live/chat_live.ex` — async pipeline restructure, new assigns, stream chunk handler, stream completion/error cleanup
- `test/unit/live/chat_live_rag_unit_test.exs`
- `test/integration/live/chat_live_rag_test.exs`
- `test/e2e/sp_04_04_chatlive_rag_e2e_test.exs` (tagged `:e2e`)

### Out

- HEEx template card rendering and product card component (SP-04-05)
- "Searching..." indicator in the template (SP-04-05)
- `StyleAdvisor`, `QueryUnderstander`, `ResponseParser` internals (prior sprints)

### Cross-Sprint Dependencies (explicit)

- **SP-04-01 must be complete:** `QueryUnderstander.evaluate/1` and `StyleAdvisor.build_prompt/2` are called here.
- **SP-04-02 must be complete:** `ResponseParser.parse/2` is called in the stream chunk handler.
- **SP-04-03 must be complete:** `StyleAdvisor.augment/2` signature and token budget parameter are finalized there. This sprint passes `conversation_tokens:` read from `usage_records` in socket assigns.
- **Token budget data source:** ChatLive reads the current conversation's total token count from `socket.assigns.usage_total_tokens` (already populated by the existing usage tracking in SP-01-07 / SPRINT-16). Pass it as `conversation_tokens: socket.assigns.usage_total_tokens` when calling `augment/2`.

---

## Architecture Requirement

`handle_event("send_message")` **must** be split into two phases to allow `rag_status: :searching` to be emitted to the client before the blocking `augment/2` call begins. Without this split, the client never sees the `:searching` state.

**Required pattern:**

```elixir
def handle_event("send_message", %{"input" => text}, socket) do
  text = String.trim(text)
  if text == "" or socket.assigns.is_sending do
    {:noreply, socket}
  else
    socket =
      socket
      |> assign(:rag_status, :searching)
      |> assign(:input, "")
      |> assign(:is_sending, true)
      |> assign(:hero_state, false)
      |> push_user_message(text)
    send(self(), {:do_rag, text})
    {:noreply, socket}           # :searching emitted here before augment starts
  end
end

def handle_info({:do_rag, text}, socket) do
  {:ok, prompt, items} = StyleAdvisor.augment(text,
    conversation_tokens: socket.assigns.usage_total_tokens
  )
  case QueryUnderstander.evaluate(items) do
    {:clarify, question} ->
      socket =
        socket
        |> push_assistant_message(question)
        |> assign(:rag_status, :idle)
        |> assign(:is_sending, false)
      {:noreply, socket}

    {:recommend, _items} ->
      socket =
        socket
        |> assign(:rag_status, :streaming)
        |> assign(:response_parser_buffer, "")
        |> assign(:pending_cards, [])
      send_to_streaming_pipeline(prompt, self())
      {:noreply, socket}
  end
end
```

This pattern is **required by the tests**. An implementation that calls `augment/2`
synchronously inside `handle_event` will fail I1 and U1.

---

## Tests

### E2E (tagged `:e2e`, require seeded DB with embeddings)

---

**E1 — Full RAG flow: rag_status transitions and pending_cards populated**

```elixir
# Requires items seeded with embeddings
{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "vintage denim jacket under $60"})

# After handle_event returns: :searching
assert view |> element("[data-rag-status]") |> render() =~ "searching"

# After stream completes
# (use assert_receive or wait for stream_done with a test timeout)
assert eventually(fn ->
  html = render(view)
  html =~ "data-rag-status=\"idle\""
end, timeout: 8000)

assert view.assigns.pending_cards != []
assert Enum.all?(view.assigns.pending_cards, &match?(%ClothingItem{}, &1.item))
```

Failure guarded: full integration broken; cards never reaching socket assigns.

---

**E2 — Clarify path: clarifying question sent without OpenAI call**

```elixir
# Stub augment to return items all below threshold
stub(MockStyleAdvisor, :augment, fn _, _ ->
  items = [%ClothingItem{rrf_score: 0.005}]
  {:ok, "base prompt", items}
end)
{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "xyz"})

# No streaming started; clarifying question appears
html = render(view)
assert html =~ "Could you tell me more?"
assert view.assigns.rag_status == :idle
assert view.assigns.is_sending == false
```

Failure guarded: `:clarify` path calling the streaming pipeline anyway; rag_status
stuck at `:searching` after clarify response.

---

**E3 — Empty search: base prompt used, streaming proceeds normally**

```elixir
stub(MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base prompt", []} end)
{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "what time is it?"})

assert eventually(fn ->
  view.assigns.rag_status == :idle
end, timeout: 5000)
refute render(view) =~ "AVAILABLE ITEMS"
```

Failure guarded: empty items list crashing the pipeline; rag_status stuck.

---

### Integration

All in `test/integration/live/chat_live_rag_test.exs`.

---

**I1 — :searching emitted to client before augment begins**

This test requires a blocking stub to interlock timing.

```elixir
test_pid = self()

stub(MockStyleAdvisor, :augment, fn _, _ ->
  # Signal test that augment has been entered
  send(test_pid, :augment_started)
  # Block until test releases us
  receive do: (:release -> :ok)
  {:ok, "base", []}
end)

{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "query"})

# Verify :searching is visible before augment returns
assert_receive :augment_started, 1000
assert view.assigns.rag_status == :searching

# Release augment
send(augment_task_pid, :release)
```

Failure guarded: augment called synchronously in handle_event — :searching state
never emitted separately; client always sees :idle → :streaming with no pause.

---

**I2 — response_parser_buffer reset to "" on stream completion**

```elixir
# Drive view to streaming state with a partial buffer
socket_with_buffer = assign(socket, response_parser_buffer: "partial text", rag_status: :streaming)
{:noreply, socket_after} = ChatLive.handle_info(:stream_done, socket_with_buffer)
assert socket_after.assigns.response_parser_buffer == ""
assert socket_after.assigns.rag_status == :idle
```

Failure guarded: stale buffer from a previous message contaminating the next parse
call, extracting phantom cards from old content.

---

**I3 — pending_cards populated with full ClothingItem structs via DB lookup**

```elixir
item = insert(:clothing_item)  # factory-seeded item with known id
card_json = ~s({"cards": [{"item_id": #{item.id}, "reason": "Good pick"}]})

# Simulate a stream chunk arriving
socket_streaming = assign(socket, rag_status: :streaming, response_parser_buffer: "", pending_cards: [])
{:noreply, socket_after} = ChatLive.handle_info({:stream_token, card_json}, socket_streaming)

assert length(socket_after.assigns.pending_cards) == 1
card = hd(socket_after.assigns.pending_cards)
assert card.item.id == item.id
assert card.reason == "Good pick"
assert match?(%ClothingItem{}, card.item)
```

Failure guarded: pending_cards containing raw maps instead of struct-wrapped items;
item_id lookup not happening.

---

**I4 — Existing non-RAG message handling unchanged after refactor**

```elixir
# Drive to clarify path (no streaming) and verify conversation persists
stub(MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base", [%ClothingItem{rrf_score: 0.001}]} end)
{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "hello"})
html = render(view)
assert html =~ "hello"
assert html =~ "Could you tell me more?"
assert view.assigns.rag_status == :idle
```

Failure guarded: RAG restructure breaking the message display path; assigns
corrupted for subsequent messages.

---

**I5 — Multiple sequential stream chunks accumulate pending_cards correctly**

```elixir
item_1 = insert(:clothing_item)
item_2 = insert(:clothing_item)
chunk_1 = ~s(Some text )
chunk_2 = ~s({"cards": [{"item_id": #{item_1.id}, "reason": "A"}]})
chunk_3 = ~s({"cards": [{"item_id": #{item_2.id}, "reason": "B"}]})

socket = assign(socket, rag_status: :streaming, response_parser_buffer: "", pending_cards: [])
{:noreply, s1} = ChatLive.handle_info({:stream_token, chunk_1}, socket)
{:noreply, s2} = ChatLive.handle_info({:stream_token, chunk_2}, s1)
{:noreply, s3} = ChatLive.handle_info({:stream_token, chunk_3}, s2)

assert length(s3.assigns.pending_cards) == 2
ids = Enum.map(s3.assigns.pending_cards, & &1.item.id)
assert item_1.id in ids
assert item_2.id in ids
```

Failure guarded: second chunk overwriting buffer from first, dropping the first card.

---

**M1 — nil DB lookup for unknown item_id is silently dropped, valid cards kept**

```elixir
real_item = insert(:clothing_item)
card_json = ~s({"cards": [
  {"item_id": #{real_item.id}, "reason": "Good"},
  {"item_id": 99999, "reason": "Ghost"}
]})
socket = assign(socket, rag_status: :streaming, response_parser_buffer: "", pending_cards: [])
{:noreply, socket_after} = ChatLive.handle_info({:stream_token, card_json}, socket)

assert length(socket_after.assigns.pending_cards) == 1
assert hd(socket_after.assigns.pending_cards).item.id == real_item.id
```

Failure guarded: nil item crashing template render; valid card dropped alongside
an invalid one.

---

**M2 — augment error {:ok, base_prompt, []} does not crash ChatLive**

```elixir
stub(MockStyleAdvisor, :augment, fn _, _ -> {:ok, "base prompt", []} end)
{:ok, view, _} = live(conn, "/")
view |> form("#chat-form") |> render_submit(%{"input" => "anything"})
assert Process.alive?(view.pid)
assert_eventually(fn -> view.assigns.rag_status == :idle end, timeout: 3000)
```

Failure guarded: `{:ok, base_prompt, []}` hitting a pattern match that expects
non-empty items, raising `FunctionClauseError` and killing the LiveView process.

---

**M3 — :stream_error resets rag_status, buffer, and pending_cards**

```elixir
socket_mid_stream = assign(socket,
  rag_status: :streaming,
  response_parser_buffer: "partial json",
  pending_cards: [%{item: %ClothingItem{}, reason: "partial"}]
)
{:noreply, socket_after} = ChatLive.handle_info({:stream_error, :timeout}, socket_mid_stream)
assert socket_after.assigns.rag_status == :idle
assert socket_after.assigns.response_parser_buffer == ""
assert socket_after.assigns.pending_cards == []
assert socket_after.assigns.is_sending == false
```

Failure guarded: rag_status stuck at :streaming after network failure; composer
permanently disabled; partial buffer contaminating the next message.

---

### Unit

In `test/unit/live/chat_live_rag_unit_test.exs`.

---

**U1 — rag_status is :searching after handle_event("send_message") returns**

```elixir
{:noreply, socket_after} =
  ChatLive.handle_event("send_message", %{"input" => "hello"}, socket_idle)
assert socket_after.assigns.rag_status == :searching
```

Note: this test passes only if the architecture sends `{:do_rag, text}` to self
and returns immediately. If `augment/2` is called inline, this test fails.

Failure guarded: :searching state not set before async work begins; the async
restructure being skipped.

---

**U2 — Initial socket assigns include all RAG-related fields on mount**

```elixir
{:ok, socket} = ChatLive.mount(%{}, %{}, build_socket())
assert socket.assigns.rag_status == :idle
assert socket.assigns.response_parser_buffer == ""
assert socket.assigns.pending_cards == []
```

Failure guarded: missing assigns causing KeyError on first message; rag_status
being undefined when the template reads it on initial render.

---

## Implementation Tasks

- [x] Write all tests (E1–E3, I1–I5, M1–M3, U1–U2) — all failing
- [x] Add to `mount/3` socket assigns: `rag_status: :idle`, `response_parser_buffer: ""`, `pending_cards: []`
- [x] **Restructure `handle_event("send_message")`** (architecture requirement):
  - [x] Set `rag_status: :searching`, `input: ""`, `is_sending: true`, `hero_state: false`
  - [x] Append user message to conversation
  - [x] `send(self(), {:do_rag, text})`
  - [x] Return `{:noreply, socket}` — emit :searching before any blocking work
- [x] Implement `handle_info({:do_rag, text}, socket)`:
  - [x] Call `StyleAdvisor.augment(text, conversation_tokens: socket.assigns.usage_total_tokens)`
  - [x] Call `QueryUnderstander.evaluate(items)`
  - [x] On `{:clarify, question}`: append question as assistant message, `assign(rag_status: :idle, is_sending: false)`
  - [x] On `{:recommend, _}`: `assign(rag_status: :streaming, response_parser_buffer: "", pending_cards: [])`, pass `augmented_prompt` to streaming pipeline
- [x] Update `handle_info({:stream_token, chunk}, socket)`:
  - [x] Call `ResponseParser.parse(chunk, socket.assigns.response_parser_buffer)`
  - [x] Update `response_parser_buffer` with returned remaining buffer
  - [x] For each card returned: look up `Clothing.get_item(card.item_id)` — skip if nil
  - [x] Append valid `%{item: %ClothingItem{}, reason: card.reason}` entries to `pending_cards`
- [x] Update `handle_info(:stream_done, socket)`:
  - [x] Move `pending_cards` into message struct for permanent rendering
  - [x] `assign(response_parser_buffer: "", pending_cards: [], rag_status: :idle, is_sending: false)`
- [x] Update `handle_info({:stream_error, _reason}, socket)`:
  - [x] `assign(rag_status: :idle, response_parser_buffer: "", pending_cards: [], is_sending: false)`
- [x] Run `mix test test/unit/live/chat_live_rag_unit_test.exs test/integration/live/chat_live_rag_test.exs` — all green
- [x] Run `mix test` full suite — zero regressions (2 pre-existing failures unrelated to this sprint)

---

## Definition of Done

- [ ] All 13 non-E2E tests pass
- [ ] E2E tests pass on seeded DB (`mix test --include e2e test/e2e/sp_04_04_chatlive_rag_e2e_test.exs`)
- [ ] `rag_status` is never left in `:searching` or `:streaming` after any code path completes (including error paths)
- [ ] `response_parser_buffer` and `pending_cards` are always reset on stream completion and stream error
- [ ] No crash path reachable from any combination of augment returning `{:ok, _, []}`, ResponseParser returning nil-id cards, or stream_error arriving mid-buffer
- [ ] `mix test` full suite green — zero regressions to existing chat tests
- [ ] Card rendering is **not** in scope — template renders pending_cards as a raw list or ignores it; SP-04-05 owns that
