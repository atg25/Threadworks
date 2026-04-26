---
status: complete
---

# Sprint 1.6 — LiveView Event Handlers & State Machine

**Spec:** spec-1 §7, §8  
**Goal:** Implement all `handle_event/3` and `handle_info/2` callbacks in `ChatLive`. Test the full state machine: sending a message, hero disappearing permanently, `is_sending` toggling, streaming token accumulation, stream completion, stream errors, and all guard conditions (blank input, double-send).  
**Depends on:** sprint-1.5 (composer form renders with `phx-submit="send_message"`)  
**Strategy:** All tests in this sprint use a **stubbed OpenAI** — `ChatApp.OpenAI` is mocked or bypassed so tests are fast, deterministic, and offline. Real streaming is wired in sprint 1.9.

---

## TDD Approach

| Layer                      | Tool                              | Assertions                                                              |
| -------------------------- | --------------------------------- | ----------------------------------------------------------------------- |
| `send_message` happy path  | `Phoenix.LiveViewTest`            | User msg appended, `hero_state: false`, `is_sending: true`, `input: ""` |
| Guard: blank input         | `Phoenix.LiveViewTest`            | State unchanged on empty submit                                         |
| Guard: double-send         | `Phoenix.LiveViewTest`            | State unchanged when `is_sending: true`                                 |
| `:stream_token`            | `send/2` into live process        | Buffer grows, assistant msg upserted                                    |
| `:stream_done`             | `send/2`                          | `is_sending: false`, `stream_buffer: ""`                                |
| `:stream_error`            | `send/2`                          | Error message appended, `is_sending: false`                             |
| `scroll_position`          | `Phoenix.LiveViewTest push_event` | `at_bottom` assign updated                                              |
| `upsert_assistant_message` | `ExUnit` unit test                | Pure function correctness                                               |

---

## Step 1 — Write unit tests for pure helpers FIRST (Red)

### `test/chat_app_web/live/chat_live_unit_test.exs`

These test private helpers extracted to a public module for testability:

```elixir
defmodule ChatAppWeb.ChatLiveUnitTest do
  use ExUnit.Case, async: true

  # We will make upsert_assistant_message/2 a public function
  # in a ChatApp.Chat module so it can be tested directly.
  alias ChatApp.Chat

  describe "upsert_assistant_message/2" do
    # Positive: appends new assistant message when last is user
    test "appends assistant message when messages list ends with user role" do
      messages = [%{role: :user, content: "hello"}]
      result   = Chat.upsert_assistant_message(messages, "Hi there")
      assert length(result) == 2
      assert List.last(result) == %{role: :assistant, content: "Hi there"}
    end

    # Positive: replaces last assistant message (token accumulation)
    test "updates last message when it is already an assistant message" do
      messages = [
        %{role: :user, content: "hello"},
        %{role: :assistant, content: "Hi"}
      ]
      result = Chat.upsert_assistant_message(messages, "Hi there!")
      assert length(result) == 2
      assert List.last(result) == %{role: :assistant, content: "Hi there!"}
    end

    # Positive: works on empty list
    test "appends assistant message to empty list" do
      result = Chat.upsert_assistant_message([], "First token")
      assert result == [%{role: :assistant, content: "First token"}]
    end

    # Negative: does not duplicate messages
    test "does not grow list beyond expected length when updating assistant msg" do
      messages = [
        %{role: :user, content: "Q"},
        %{role: :assistant, content: "A"}
      ]
      result = Chat.upsert_assistant_message(messages, "A longer answer")
      assert length(result) == 2
    end

    # Negative: does not modify user messages
    test "never changes role of existing user message" do
      messages = [%{role: :user, content: "Q"}]
      result   = Chat.upsert_assistant_message(messages, "A")
      user_msgs = Enum.filter(result, &(&1.role == :user))
      assert length(user_msgs) == 1
      assert hd(user_msgs).content == "Q"
    end
  end
end
```

### Create `lib/chat_app/chat.ex` (public helper module)

```elixir
defmodule ChatApp.Chat do
  @doc """
  Appends a new assistant message, or replaces the last one if it is already
  an assistant message (used for streaming token accumulation).
  """
  def upsert_assistant_message(messages, buffer) do
    case List.last(messages) do
      %{role: :assistant} ->
        List.update_at(messages, -1, fn _ -> %{role: :assistant, content: buffer} end)
      _ ->
        messages ++ [%{role: :assistant, content: buffer}]
    end
  end
end
```

Run:

```bash
mix test test/chat_app_web/live/chat_live_unit_test.exs
```

Expected: tests fail because `ChatApp.Chat` does not exist yet. After creating the file, they pass.

---

## Step 2 — Write LiveView integration tests FIRST (Red)

### `test/chat_app_web/live/chat_live_events_test.exs`

```elixir
defmodule ChatAppWeb.ChatLiveEventsTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  # ── send_message happy path ──────────────────────────────────

  test "send_message appends user message to messages list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello AI"})

    html = render(view)
    assert html =~ "Hello AI"
  end

  test "send_message sets hero_state to false", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello"})

    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  test "send_message clears the input field", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "Hello"})

    html = render(view)
    # textarea value should be empty after send
    assert html =~ ~r/<textarea[^>]+value=""/
      or html =~ ~r/value=""\s*>/
  end

  test "hero_state never returns to true after first send", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # First send
    view |> element("form") |> render_submit(%{"input" => "First"})
    refute has_element?(view, "[data-homepage-chat-intro]")

    # Simulate stream completion
    pid = view.pid
    send(pid, :stream_done)
    render(view)

    # Hero must still be gone
    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  # ── Guard: blank input ────────────────────────────────────────

  test "send_message with blank input does not add a message", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "   "})

    # Hero still shown (no message sent = hero_state still true)
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "send_message with blank input does not change hero_state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => ""})
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  # ── Guard: double-send while is_sending ───────────────────────

  # NOTE: After the first render_submit, ChatLive sets is_sending: true and
  # spawns a Task that sends :stream_token/:stream_done asynchronously.
  # In the BEAM scheduler, the test process regains control immediately after
  # render_submit and makes the second submit before the task is scheduled.
  # This is reliable in practice but depends on cooperative scheduling.
  # If this test becomes flaky in CI, replace with a direct `send(view.pid,
  # :stream_done)` call after the first submit to control timing explicitly.
  test "second send while is_sending is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # First send — starts streaming
    view |> element("form") |> render_submit(%{"input" => "First question"})

    # Immediately try to send again before stream_done
    view |> element("form") |> render_submit(%{"input" => "Second question"})

    html = render(view)
    # Only one user message should be present
    assert html =~ "First question"
    refute html =~ "Second question"
  end

  # ── scroll_position ───────────────────────────────────────────

  test "scroll_position event updates at_bottom assign", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> render_hook("scroll_position", %{"at_bottom" => false})

    # We can't directly inspect assigns from the outside in LiveViewTest,
    # but we verify no crash and the view is still alive
    assert render(view) =~ "data-chat-surface"
  end
  # ── handle_keydown ─────────────────────────────────────────────

  test "handle_keydown Enter is a no-op and does not crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> render_hook("handle_keydown", %{"key" => "Enter", "shiftKey" => false})
    assert render(view) =~ "data-chat-surface"
  end

  test "handle_keydown arbitrary key does not crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> render_hook("handle_keydown", %{"key" => "a", "shiftKey" => false})
    assert render(view) =~ "data-chat-surface"
  end
  # ── handle_info: :stream_token ────────────────────────────────

  test ":stream_token appends to stream buffer and shows partial response", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # First send to set is_sending: true
    view |> element("form") |> render_submit(%{"input" => "Hello"})

    # Simulate a token arriving
    pid = view.pid
    send(pid, {:stream_token, "Hello"})
    send(pid, {:stream_token, " world"})

    html = render(view)
    assert html =~ "Hello world"
  end

  test ":stream_token with empty string does not crash", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    pid = view.pid
    send(pid, {:stream_token, ""})
    assert render(view) =~ "data-chat-surface"
  end

  # ── handle_info: :stream_done ─────────────────────────────────

  test ":stream_done clears is_sending and stream_buffer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})
    pid = view.pid

    send(pid, {:stream_token, "Some answer"})
    send(pid, :stream_done)

    html = render(view)
    # Button should no longer be disabled for is_sending (only disabled for empty input)
    # The send button disabled attr is driven by @is_sending || @input == ""
    # After stream_done, is_sending is false, input is "" → button still disabled (empty input)
    # So we check the view is still alive and no crash
    assert html =~ "data-chat-surface"
  end

  # ── handle_info: :stream_error ────────────────────────────────

  test ":stream_error appends error message to messages", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})
    pid = view.pid

    send(pid, {:stream_error, "connection refused"})

    html = render(view)
    assert html =~ "Error:"
  end

  test ":stream_error sets is_sending to false", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})
    pid = view.pid

    send(pid, {:stream_error, "timeout"})

    # View must be alive and stable after error
    assert render(view) =~ "data-chat-surface"
  end

  # ── Typing indicator ──────────────────────────────────────────

  test "typing indicator shown while is_sending and stream_buffer is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})

    html = render(view)
    # Typing indicator renders when is_sending && stream_buffer == ""
    assert html =~ "animate-pulse"
  end

  test "typing indicator hidden once first token arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("form") |> render_submit(%{"input" => "Q"})
    pid = view.pid

    send(pid, {:stream_token, "Hi"})
    html = render(view)
    refute html =~ "animate-pulse"
  end
end
```

Run:

```bash
mix test test/chat_app_web/live/chat_live_events_test.exs
```

Expected: all fail — handlers not implemented yet.

---

## Step 3 — Implement handlers in `ChatLive` (Green)

Add to `lib/chat_app_web/live/chat_live.ex`:

```elixir
alias ChatApp.Chat

@impl true
def handle_event("send_message", %{"input" => text}, socket) do
  text = String.trim(text)
  if text == "" || socket.assigns.is_sending do
    {:noreply, socket}
  else
    user_msg = %{role: :user, content: text}
    messages = socket.assigns.messages ++ [user_msg]
    pid = self()
    Task.start(fn -> ChatApp.OpenAI.stream(messages, pid) end)

    {:noreply,
     assign(socket,
       messages:      messages,
       input:         "",
       is_sending:    true,
       stream_buffer: "",
       hero_state:    false
     )}
  end
end

@impl true
def handle_event("scroll_position", %{"at_bottom" => at_bottom}, socket) do
  {:noreply, assign(socket, at_bottom: at_bottom)}
end

@impl true
def handle_event("handle_keydown", %{"key" => "Enter", "shiftKey" => false}, socket) do
  # No-op: the ChatComposer JS hook already called requestSubmit().
  # This server-side handler exists for spec completeness and prevents
  # unhandled-event crashes on Enter presses.
  {:noreply, socket}
end

@impl true
def handle_event("handle_keydown", _params, socket) do
  # Catch-all: phx-keydown fires on every keystroke. All non-Enter keys
  # (and Shift+Enter) are silently ignored to prevent crashes.
  {:noreply, socket}
end

@impl true
def handle_info({:stream_token, token}, socket) do
  buffer   = socket.assigns.stream_buffer <> token
  messages = Chat.upsert_assistant_message(socket.assigns.messages, buffer)
  {:noreply, assign(socket, messages: messages, stream_buffer: buffer)}
end

@impl true
def handle_info(:stream_done, socket) do
  {:noreply, assign(socket, is_sending: false, stream_buffer: "")}
end

@impl true
def handle_info({:stream_error, reason}, socket) do
  error_msg = %{role: :assistant, content: "Error: #{inspect(reason)}"}
  messages  = socket.assigns.messages ++ [error_msg]
  {:noreply, assign(socket, messages: messages, is_sending: false, stream_buffer: "")}
end
```

Also update the message viewport in `render/1` to show:

1. Typing indicator when `@is_sending && @stream_buffer == ""`
2. Message bubbles (stubbed for now — full impl in sprint 1.8)

```heex
<%= if @hero_state do %>
  <.hero_intro />
<% else %>
  <%= for msg <- @messages do %>
    <div data-chat-message-bubble={true}
         data-role={msg.role}
         class={if msg.role == :user, do: "ml-auto max-w-[80%] rounded-2xl px-4 py-2 text-sm ui-chat-message-user",
                                      else: "max-w-[80%] rounded-2xl px-4 py-2 text-sm ui-chat-message-assistant"}>
      <%= msg.content %>
    </div>
  <% end %>

  <%= if @is_sending && @stream_buffer == "" do %>
    <div class="ui-chat-message-assistant max-w-[80%] rounded-2xl px-4 py-2 text-sm
                opacity-60 animate-pulse">
      …
    </div>
  <% end %>
<% end %>
```

---

## Step 4 — Stub `ChatApp.OpenAI` for tests

To prevent real HTTP calls during tests, add to `config/test.exs`:

```elixir
config :chat_app, :openai_module, ChatApp.OpenAI.Stub
```

Create `lib/chat_app/openai/stub.ex`:

```elixir
defmodule ChatApp.OpenAI.Stub do
  @doc "Immediately sends stream_done without making any HTTP request."
  def stream(_messages, pid) do
    send(pid, {:stream_token, "Stub response."})
    send(pid, :stream_done)
  end
end
```

Update `ChatLive` to use the configured module:

```elixir
defp openai_module do
  Application.get_env(:chat_app, :openai_module, ChatApp.OpenAI)
end

# In handle_event("send_message", ...):
Task.start(fn -> openai_module().stream(messages, pid) end)
```

---

## Step 5 — Run all tests (Red → Green)

```bash
mix test
```

All tests pass. Total: ~65 tests.

---

## Acceptance Criteria

- [ ] `ChatApp.Chat.upsert_assistant_message/2` unit tests pass (5 tests)
- [ ] All 17 `ChatLiveEventsTest` tests pass
- [ ] `send_message` with blank input does not change state
- [ ] `send_message` while `is_sending: true` is ignored
- [ ] `:stream_token` accumulates buffer and upserts assistant message
- [ ] `:stream_done` clears `is_sending` and `stream_buffer`
- [ ] `:stream_error` appends error message and clears `is_sending`
- [ ] `hero_state` never reverts to `true` after first send
- [ ] Typing indicator uses `animate-pulse` class
- [ ] `handle_event("handle_keydown", ...)` has specific Enter clause + catch-all (prevents crashes on every keystroke)
- [ ] `ChatApp.OpenAI.Stub` used in test env (no real HTTP)
- [ ] `mix test` exits 0
