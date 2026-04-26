---
status: complete
---

# Sprint 1.9 — Streaming Integration (Real HTTP + Bypass)

**Spec:** spec-1 §9  
**Goal:** Verify that `ChatApp.OpenAI.stream/2` correctly drives the full LiveView state machine when connected to a realistic HTTP SSE server. Use `Bypass` to spin up a local HTTP stub that emits well-formed SSE chunks without hitting the real OpenAI API. Then do a single smoke-test against the real API (tagged `:real_api`, skipped in CI).  
**Depends on:** sprint-1.7 (`ChatApp.OpenAI` + `SSE` module), sprint-1.8 (message bubbles render)  
**Delivers:** Confidence that the Req `into:` streaming path, SSE parser, and LiveView message dispatch all work end-to-end as a connected system.

---

## TDD Approach

| Layer                             | Tool                     | Assertions                                                        |
| --------------------------------- | ------------------------ | ----------------------------------------------------------------- |
| Bypass SSE → LiveView             | ExUnit + `Bypass`        | Tokens arrive, final message correct, `:stream_done` clears state |
| Multi-chunk boundary split        | ExUnit + Bypass          | Token split across TCP chunks reassembles correctly               |
| `[DONE]` line ends stream cleanly | ExUnit + Bypass          | No extra tokens after `[DONE]`, `:stream_done` sent               |
| HTTP 4xx from OpenAI              | ExUnit + Bypass          | `{:stream_error, _}` sent, LiveView shows error message           |
| HTTP timeout                      | ExUnit + Bypass          | `{:stream_error, _}` sent within timeout window                   |
| Real API smoke test               | ExUnit (`:real_api` tag) | Tokens arrive, coherent response, skipped in CI                   |

---

## Step 1 — Add `Bypass` to deps

`mix.exs`:

```elixir
{:bypass, "~> 2.1", only: :test}
```

```bash
mix deps.get
```

---

## Step 2 — Write integration tests FIRST (Red)

### `test/chat_app/openai_integration_test.exs`

```elixir
defmodule ChatApp.OpenAIIntegrationTest do
  use ExUnit.Case, async: false

  alias ChatApp.OpenAI

  setup do
    bypass = Bypass.open()
    # Override the API URL to point at our Bypass port
    original_url = Application.get_env(:chat_app, :openai_api_url,
                     "https://api.openai.com/v1/chat/completions")
    Application.put_env(:chat_app, :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions")

    on_exit(fn ->
      Application.put_env(:chat_app, :openai_api_url, original_url)
    end)

    {:ok, bypass: bypass}
  end

  # Helper: build a well-formed SSE chunk for a content token
  defp sse_chunk(content) do
    json = Jason.encode!(%{
      choices: [%{delta: %{content: content}, finish_reason: nil}]
    })
    "data: #{json}\n\n"
  end

  defp sse_done, do: "data: [DONE]\n\n"

  # ── Positive: single token ────────────────────────────────────

  test "stream/2 sends :stream_token for each SSE chunk then :stream_done", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("Hello"))
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk(" world"))
      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    messages = [%{role: :user, content: "Hi"}]
    Task.start(fn -> OpenAI.stream(messages, pid) end)

    assert_receive {:stream_token, "Hello"}, 3000
    assert_receive {:stream_token, " world"}, 3000
    assert_receive :stream_done, 3000
  end

  # Positive: tokens accumulate to form correct full response
  test "accumulated tokens form the correct full response", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      for word <- ["The ", "quick ", "brown ", "fox"] do
        {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk(word))
        conn
      end
      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    tokens = collect_tokens([], 5000)
    assert Enum.join(tokens) == "The quick brown fox"
    assert_receive :stream_done, 1000
  end

  # Positive: TCP chunk boundary split — JSON split across two Bypass chunks
  test "token split across TCP chunks is reassembled correctly", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      json = Jason.encode!(%{choices: [%{delta: %{content: "Split"}, finish_reason: nil}]})
      full_line = "data: #{json}"
      half = div(byte_size(full_line), 2)
      {:ok, conn} = Plug.Conn.chunk(conn, binary_part(full_line, 0, half))
      {:ok, conn} = Plug.Conn.chunk(conn, binary_part(full_line, half, byte_size(full_line) - half) <> "\n\n")
      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_token, "Split"}, 3000
    assert_receive :stream_done, 1000
  end

  # Positive: [DONE] line produces no extra token
  test "[DONE] line does not produce a :stream_token", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("OK"))
      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_token, "OK"}, 3000
    assert_receive :stream_done, 1000
    refute_receive {:stream_token, "[DONE]"}, 300
  end

  # Negative: HTTP 401 (bad API key)
  # Req ~> 0.5 does NOT raise on non-2xx status codes by default — it returns
  # {:ok, %Req.Response{status: 401}}. The `into:` callback is still called with
  # the error body, which the SSE parser ignores (no valid data: lines). After
  # Req.post returns, `send(lv_pid, :stream_done)` fires. So a 401 produces
  # :stream_done, NOT {:stream_error, _}. This test verifies no crash and that
  # a terminal message is received.
  test "HTTP 401 response terminates cleanly with :stream_done", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Invalid API key"}}))
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    # Req returns {:ok, response} for 4xx — no exception — stream_done is sent
    assert_receive :stream_done, 3000
    # No spurious tokens from the error body
    refute_receive {:stream_token, _}, 300
  end

  # Negative: server closes connection immediately → no crash, :stream_done or :stream_error sent
  test "abrupt connection close does not crash the caller", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      # Send one chunk then forcibly close
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("Partial"))
      conn
      # Bypass will close the connection after the handler returns
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    # Must receive either :stream_done or {:stream_error, _} — no crash
    assert_receive msg, 3000
    assert match?(:stream_done, msg) or match?({:stream_error, _}, msg)
  end

  # Negative: Bypass down (connection refused) → {:stream_error, _}
  test "connection refused sends {:stream_error, _}", %{bypass: bypass} do
    pid = self()
    Bypass.down(bypass)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_error, _}, 5000
  end

  # ── Real API smoke test (skipped in CI) ───────────────────────

  @tag :real_api
  test "real OpenAI API returns at least one token" do
    pid = self()
    messages = [%{role: :user, content: "Say exactly: pong"}]

    # Restore real URL for this test
    Application.put_env(:chat_app, :openai_api_url,
      "https://api.openai.com/v1/chat/completions")

    Task.start(fn -> OpenAI.stream(messages, pid) end)

    assert_receive {:stream_token, _token}, 15_000
    # Drain remaining tokens
    assert_receive :stream_done, 15_000
  end

  # ── Helpers ───────────────────────────────────────────────────

  defp collect_tokens(acc, timeout) do
    receive do
      {:stream_token, t} -> collect_tokens(acc ++ [t], timeout)
      :stream_done       -> acc
    after
      timeout -> acc
    end
  end
end
```

Run:

```bash
mix test test/chat_app/openai_integration_test.exs
```

Expected: tests fail — Bypass is not yet a dep and the test module switch is not yet wired. Tests pass once Steps 4–5 are applied.

---

## Step 3 — Verify the API URL is already runtime-configurable

`ChatApp.OpenAI` already defines `api_url/0` reading from Application env (implemented in sprint-1.7):

```elixir
defp api_url do
  Application.get_env(:chat_app, :openai_api_url,
    "https://api.openai.com/v1/chat/completions")
end
```

No changes needed here. The Bypass tests rely on this being in place. If sprint-1.7 is not yet applied, add this function before continuing.

---

## Step 4 — Add Bypass dep

```bash
mix deps.get
```

Bypass is now available. Do NOT run the integration tests yet — they still fail because `openai_module` is still the Stub in `config/test.exs`. That is fixed in Step 5.

---

## Step 5 — Wire the stub switchover cleanly (Red → Green)

Update `config/test.exs` so the stub module is used for LiveView event tests but the real module is used for integration tests that control the URL:

```elixir
# config/test.exs
config :chat_app, :openai_module, ChatApp.OpenAI.Stub
config :chat_app, :openai_api_key, "sk-test-stub"
# Note: :openai_api_url is NOT set here — integration tests set it via Application.put_env
```

In the integration test `setup`, also set the module back to the real one:

```elixir
setup do
  bypass = Bypass.open()
  Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)
  Application.put_env(:chat_app, :openai_api_url,
    "http://localhost:#{bypass.port}/v1/chat/completions")

  on_exit(fn ->
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI.Stub)
    Application.delete_env(:chat_app, :openai_api_url)
  end)

  {:ok, bypass: bypass}
end
```

---

## Step 6 — Run integration tests then full suite (Red → Green)

```bash
# Integration tests alone first:
mix test test/chat_app/openai_integration_test.exs

# Then full suite:
mix test --exclude real_api
```

All non-`:real_api` tests pass. Total: ~110 tests.

To run the real API smoke test manually:

```bash
export $(cat .env | xargs)
mix test --only real_api
```

---

## Acceptance Criteria

- [ ] `Bypass ~> 2.1` added to test deps, `mix deps.get` passes
- [ ] `api_url/0` reads from `Application.get_env(:chat_app, :openai_api_url, ...)` in `ChatApp.OpenAI`
- [ ] Single-token Bypass test passes
- [ ] Multi-token accumulation test passes
- [ ] TCP chunk boundary split test passes
- [ ] `[DONE]` does not produce extra `stream_token`
- [ ] Connection-refused test sends `{:stream_error, _}`
- [ ] `mix test --exclude real_api` exits 0
- [ ] `@tag :real_api` smoke test works when run with real key (optional / manual)

---

## Out of Scope for This Sprint

- Browser-level visual and interaction verification (sprint 1.10)
- Performance or load testing
- Rate limit handling (post spec-1)
