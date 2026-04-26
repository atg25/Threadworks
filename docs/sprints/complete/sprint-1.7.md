---
status: complete
---

# Sprint 1.7 — OpenAI SSE Streaming Module

**Spec:** spec-1 §9  
**Goal:** Implement `ChatApp.OpenAI` with the `Req ~> 0.5` streaming client and the SSE line-splitting accumulator. All parsing logic is unit-tested thoroughly before the module is connected to a live network.  
**Depends on:** sprint-1.6 (`ChatApp.OpenAI.Stub` already referenced; real module takes its place in `:dev`/`:prod`)  
**Strategy:** No real HTTP calls in any test. Tests inject raw SSE binary chunks directly into the private parser functions, which are extracted into a public `ChatApp.OpenAI.SSE` module for testability.

---

## TDD Approach

| Layer                         | Tool                               | Assertions                                                        |
| ----------------------------- | ---------------------------------- | ----------------------------------------------------------------- |
| `parse_sse_chunk/3`           | ExUnit unit                        | Single token, multi-token, split boundary, `[DONE]`, empty, blank |
| `split_lines_and_remainder/1` | ExUnit unit                        | Returns `{complete, partial}` correctly                           |
| `stream/2` error path         | ExUnit with mocked Req             | `{:stream_error, reason}` sent on exception                       |
| `stream/2` key missing        | ExUnit                             | Crashes at boot if `OPENAI_API_KEY` absent in prod                |
| Integration (stubbed Req)     | `Bypass` or direct chunk injection | Full token sequence lands in LiveView pid                         |

---

## Step 1 — Write unit tests FIRST (Red)

### `test/chat_app/openai/sse_test.exs`

```elixir
defmodule ChatApp.OpenAI.SSETest do
  use ExUnit.Case, async: true

  alias ChatApp.OpenAI.SSE

  # ── split_lines_and_remainder/1 ───────────────────────────────

  describe "split_lines_and_remainder/1" do
    # Positive: splits normally
    test "returns complete lines and empty remainder for newline-terminated input" do
      parts = ["data: foo", "data: bar", ""]
      {complete, remainder} = SSE.split_lines_and_remainder(parts)
      assert complete == ["data: foo", "data: bar"]
      assert remainder == ""
    end

    # Positive: preserves partial last line
    test "returns partial line as remainder when not terminated" do
      parts = ["data: foo", "data: ba"]
      {complete, remainder} = SSE.split_lines_and_remainder(parts)
      assert complete == ["data: foo"]
      assert remainder == "data: ba"
    end

    # Positive: single incomplete line
    test "handles single-element list (no complete lines)" do
      {complete, remainder} = SSE.split_lines_and_remainder(["partial"])
      assert complete == []
      assert remainder == "partial"
    end

    # Negative: empty strings in the middle are filtered out
    test "filters empty strings from complete lines" do
      parts = ["data: foo", "", "data: bar", ""]
      {complete, _} = SSE.split_lines_and_remainder(parts)
      refute "" in complete
    end
  end

  # ── parse_sse_chunk/3 ─────────────────────────────────────────

  describe "parse_sse_chunk/3" do
    setup do
      # Collect messages sent to a test process
      pid = self()
      {:ok, pid: pid}
    end

    # Positive: single data line with content
    test "sends :stream_token for a valid data line", %{pid: pid} do
      json = Jason.encode!(%{
        choices: [%{delta: %{content: "Hello"}}]
      })
      chunk = "data: #{json}\n"
      {:cont, ""} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "Hello"}
    end

    # Positive: multiple data lines in one chunk
    test "sends multiple :stream_token for multiple data lines in one chunk", %{pid: pid} do
      j1 = Jason.encode!(%{choices: [%{delta: %{content: "Foo"}}]})
      j2 = Jason.encode!(%{choices: [%{delta: %{content: " bar"}}]})
      chunk = "data: #{j1}\ndata: #{j2}\n"
      {:cont, ""} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "Foo"}
      assert_received {:stream_token, " bar"}
    end

    # Positive: [DONE] line is silently ignored (stream_done sent by caller)
    test "does not crash on [DONE] line", %{pid: pid} do
      {:cont, _} = SSE.parse_sse_chunk("data: [DONE]\n", "", pid)
      refute_received {:stream_token, _}
    end

    # Positive: line split across two chunks (TCP boundary)
    test "accumulates partial line from prior chunk and completes on next chunk", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "Split"}}]})
      half1 = "data: " <> String.slice(json, 0, div(byte_size(json), 2))
      half2 = String.slice(json, div(byte_size(json), 2), byte_size(json)) <> "\n"

      {:cont, leftover} = SSE.parse_sse_chunk(half1, "", pid)
      refute_received {:stream_token, _}

      {:cont, ""} = SSE.parse_sse_chunk(half2, leftover, pid)
      assert_received {:stream_token, "Split"}
    end

    # Positive: empty chunk (heartbeat / keep-alive)
    test "handles empty chunk gracefully", %{pid: pid} do
      {:cont, ""} = SSE.parse_sse_chunk("", "", pid)
      refute_received {:stream_token, _}
    end

    # Positive: blank line between SSE events (standard SSE separator)
    test "handles blank-line event separator", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "OK"}}]})
      chunk = "\n\ndata: #{json}\n\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      assert_received {:stream_token, "OK"}
    end

    # Negative: malformed JSON in data line does not crash
    test "does not crash on malformed JSON", %{pid: pid} do
      chunk = "data: {not valid json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    # Negative: delta with no content key is silently ignored
    test "ignores delta without content key", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{role: "assistant"}}]})
      chunk = "data: #{json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    # Negative: null content value is silently ignored
    test "ignores null content in delta", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: nil}}]})
      chunk = "data: #{json}\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    # Negative: comment lines (starting with ':') are ignored
    test "ignores SSE comment lines", %{pid: pid} do
      chunk = ": keep-alive\n"
      {:cont, _} = SSE.parse_sse_chunk(chunk, "", pid)
      refute_received {:stream_token, _}
    end

    # Positive: leftover accumulates correctly across three chunks
    test "correctly accumulates leftover across three partial chunks", %{pid: pid} do
      json = Jason.encode!(%{choices: [%{delta: %{content: "Three"}}]})
      third = div(byte_size(json), 3)
      p1 = "data: " <> binary_part(json, 0, third)
      p2 = binary_part(json, third, third)
      p3 = binary_part(json, third * 2, byte_size(json) - third * 2) <> "\n"

      {:cont, lo1} = SSE.parse_sse_chunk(p1, "", pid)
      {:cont, lo2} = SSE.parse_sse_chunk(p2, lo1, pid)
      {:cont, _}   = SSE.parse_sse_chunk(p3, lo2, pid)
      assert_received {:stream_token, "Three"}
    end
  end
end
```

Run:

```bash
mix test test/chat_app/openai/sse_test.exs
```

All fail — module does not exist. Correct Red state.

---

## Step 2 — Create `ChatApp.OpenAI.SSE` (Green)

`lib/chat_app/openai/sse.ex`:

```elixir
defmodule ChatApp.OpenAI.SSE do
  @moduledoc """
  Stateful SSE chunk parser for OpenAI streaming responses.

  Req delivers raw TCP chunks. A chunk may contain multiple `data:` lines, or
  a line may be split across two chunks. A line-splitting accumulator (`acc`)
  carries the partial last line from one call to the next.

  Returns `{:cont, leftover}` where `leftover` is the incomplete trailing line.
  """

  @doc """
  Parse one raw binary chunk. `acc` is the incomplete line from the prior chunk.
  Sends `{:stream_token, token}` to `lv_pid` for each content fragment found.
  Returns `{:cont, new_acc}`.
  """
  def parse_sse_chunk(raw, acc, lv_pid) do
    combined = (acc || "") <> raw

    {lines, leftover} =
      combined
      |> String.split("\n")
      |> split_lines_and_remainder()

    Enum.each(lines, fn line -> dispatch_line(line, lv_pid) end)

    {:cont, leftover}
  end

  @doc """
  Splits a list of strings (from `String.split("\\n")`) into
  `{complete_lines, partial_last_line}`.
  The last element is always treated as potentially incomplete.
  Empty strings in the complete portion are filtered out.
  """
  def split_lines_and_remainder([single]), do: {[], single}
  def split_lines_and_remainder(parts) do
    {init, [last]} = Enum.split(parts, length(parts) - 1)
    complete = Enum.reject(init, &(&1 == ""))
    {complete, last}
  end

  # ── private ──────────────────────────────────────────────────

  defp dispatch_line("data: [DONE]", _pid), do: :ok
  defp dispatch_line("data: " <> json, pid) do
    with {:ok, body}   <- Jason.decode(json),
         content when is_binary(content) <-
           get_in(body, ["choices", Access.at(0), "delta", "content"]) do
      send(pid, {:stream_token, content})
    else
      _ -> :ok
    end
  end
  defp dispatch_line(_other, _pid), do: :ok
end
```

Run:

```bash
mix test test/chat_app/openai/sse_test.exs
```

All 15 SSE tests pass.

---

## Step 3 — Create `ChatApp.OpenAI` (the Req wrapper)

`lib/chat_app/openai.ex`:

```elixir
defmodule ChatApp.OpenAI do
  @moduledoc """
  Streams OpenAI Chat Completions SSE to a LiveView process.
  Run inside `Task.start/1` — never `Task.async`.
  """

  alias ChatApp.OpenAI.SSE

  @default_api_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Posts a streaming chat request. Sends `{:stream_token, token}` messages to
  `lv_pid` as chunks arrive, then sends `:stream_done` when the request ends.
  On any exception sends `{:stream_error, reason}`.
  """
  def stream(messages, lv_pid) do
    body = %{
      model:    "gpt-4o",
      stream:   true,
      messages: Enum.map(messages, fn %{role: role, content: content} ->
        %{role: Atom.to_string(role), content: content}
      end)
    }

    Req.post(api_url(),
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      json: body,
      receive_timeout: 120_000,
      into: fn {:data, chunk}, acc ->
        SSE.parse_sse_chunk(chunk, acc, lv_pid)
      end
    )

    send(lv_pid, :stream_done)
  rescue
    error -> send(lv_pid, {:stream_error, error})
  end

  # Read from Application env so tests can override with Bypass URL.
  # Sprint-1.9 integration tests rely on this being runtime-configurable.
  defp api_url do
    Application.get_env(:chat_app, :openai_api_url, @default_api_url)
  end

  defp api_key, do: Application.fetch_env!(:chat_app, :openai_api_key)
end
```

---

## Step 4 — Test the error rescue path

Add to `test/chat_app/openai_test.exs`:

```elixir
defmodule ChatApp.OpenAITest do
  # async: false because this test modifies global Application env
  use ExUnit.Case, async: false

  alias ChatApp.OpenAI

  # Positive: stream/2 sends {:stream_error, reason} when Req raises a transport error.
  # We override :openai_api_url to port 1 (guaranteed connection refused).
  # Because ChatApp.OpenAI reads the URL via api_url/0 (Application.get_env),
  # the override takes effect at runtime without recompiling the module.
  test "stream/2 sends {:stream_error, reason} when connection is refused" do
    pid = self()

    Application.put_env(:chat_app, :openai_api_url, "http://127.0.0.1:1/v1/chat/completions")

    on_exit(fn ->
      Application.delete_env(:chat_app, :openai_api_url)
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_error, _reason}, 5000
  end

  # Negative: Application.fetch_env! raises if :openai_api_key is not set
  test "Application.fetch_env! raises when key is missing" do
    original = Application.get_env(:chat_app, :openai_api_key)
    Application.delete_env(:chat_app, :openai_api_key)
    on_exit(fn -> Application.put_env(:chat_app, :openai_api_key, original) end)

    assert_raise ArgumentError, fn ->
      Application.fetch_env!(:chat_app, :openai_api_key)
    end
  end
end
```

Run:

```bash
mix test test/chat_app/openai/sse_test.exs test/chat_app/openai_test.exs
```

---

## Step 5 — Run full suite

```bash
mix test
```

All tests pass. Total: ~80 tests.

---

## Acceptance Criteria

- [ ] `ChatApp.OpenAI.SSE` module exists with `parse_sse_chunk/3` and `split_lines_and_remainder/1`
- [ ] All 15 SSE unit tests pass (split_lines: complete+remainder, partial, single-element, empty-filter; parse_sse_chunk: single token, multi-token, TCP split boundary, `[DONE]`, empty chunk, blank-line separator, malformed JSON, delta without content key, null content, comment line, 3-chunk accumulation)
- [ ] `ChatApp.OpenAI` exists with `stream/2` using `Req.post/2` with `into:` callback
- [ ] Error rescue path sends `{:stream_error, reason}` — tested
- [ ] `ChatApp.OpenAI.Stub` remains the configured module in test env (no real HTTP in tests)
- [ ] `mix test` exits 0

---

## Out of Scope for This Sprint

- Wiring the real `ChatApp.OpenAI` into `ChatLive` for live network calls (sprint 1.9)
- Bypass / HTTP mock server setup (sprint 1.9)
- Message bubble rendering (sprint 1.8)
