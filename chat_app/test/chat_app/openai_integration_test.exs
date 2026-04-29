defmodule ChatApp.OpenAIIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ChatApp.OpenAI

  setup do
    bypass = Bypass.open()

    # Save originals so we can restore in on_exit.
    original_module = Application.get_env(:chat_app, :openai_module)
    original_url = Application.get_env(:chat_app, :openai_api_url)
    original_req_opts = Application.get_env(:chat_app, :req_options)
    original_timeout = Application.get_env(:chat_app, :openai_receive_timeout)

    # Point the real OpenAI module at the Bypass port; clear the Req.Test plug
    # so that Bypass (not Req.Test) handles the HTTP traffic.
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

    Application.put_env(:chat_app, :req_options, [])

    on_exit(fn ->
      # Guard all four keys against nil for consistent teardown (QA Issue #4).
      if original_module do
        Application.put_env(:chat_app, :openai_module, original_module)
      else
        Application.delete_env(:chat_app, :openai_module)
      end

      if original_url do
        Application.put_env(:chat_app, :openai_api_url, original_url)
      else
        Application.delete_env(:chat_app, :openai_api_url)
      end

      if original_req_opts do
        Application.put_env(:chat_app, :req_options, original_req_opts)
      else
        Application.delete_env(:chat_app, :req_options)
      end

      if original_timeout do
        Application.put_env(:chat_app, :openai_receive_timeout, original_timeout)
      else
        Application.delete_env(:chat_app, :openai_receive_timeout)
      end
    end)

    {:ok, bypass: bypass}
  end

  # ── Helpers ────────────────────────────────────────────────────

  # Build a well-formed SSE chunk for a content token.
  defp sse_chunk(content) do
    json =
      Jason.encode!(%{
        choices: [%{delta: %{content: content}, finish_reason: nil}]
      })

    "data: #{json}\n\n"
  end

  defp sse_done, do: "data: [DONE]\n\n"

  # Drain :stream_token messages until :stream_done or timeout.
  # Uses [t | acc] + Enum.reverse for O(n) accumulation (QA Issue #15).
  defp collect_tokens(acc, timeout) do
    receive do
      {:stream_token, t} -> collect_tokens([t | acc], timeout)
      :stream_done -> Enum.reverse(acc)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  describe "buffer isolation" do
    test "calling stream/2 twice from the same process does not leak buffers between calls", %{
      bypass: bypass
    } do
      pid = self()

      # Use two distinct paths so Bypass expectations don't overwrite each other.
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions/one", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("A"))
        # Deliberately leave an incomplete trailing line (no newline) so a leaked
        # buffer would corrupt the *next* call's first SSE line.
        {:ok, conn} = Plug.Conn.chunk(conn, "data: {\"choices\":")
        conn
      end)

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions/two", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("B"))
        {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
        conn
      end)

      Application.put_env(
        :chat_app,
        :openai_api_url,
        "http://localhost:#{bypass.port}/v1/chat/completions/one"
      )

      OpenAI.stream([%{role: :user, content: "Q1"}], pid)
      assert_receive {:stream_token, "A"}, 3000
      assert_receive :stream_done, 3000

      Application.put_env(
        :chat_app,
        :openai_api_url,
        "http://localhost:#{bypass.port}/v1/chat/completions/two"
      )

      OpenAI.stream([%{role: :user, content: "Q2"}], pid)
      assert_receive {:stream_token, "B"}, 3000
      assert_receive :stream_done, 3000
    end
  end

  describe "logging" do
    test "non-2xx logs a warning with status and message_count", %{bypass: bypass} do
      pid = self()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Invalid API key"}}))
      end)

      log =
        capture_log(fn ->
          OpenAI.stream([%{role: :user, content: "USER SECRET"}], pid)
          assert_receive {:stream_error, "HTTP 401"}, 3000
        end)

      assert log =~ "non-2xx"
      assert log =~ "status: 401"
      assert log =~ "message_count: 1"
      refute log =~ "sk-"
      refute log =~ "USER SECRET"
    end

    test "transport error logs an error with reason and message_count", %{bypass: bypass} do
      pid = self()
      Bypass.down(bypass)

      log =
        capture_log(fn ->
          OpenAI.stream([%{role: :user, content: "USER SECRET"}], pid)
          assert_receive {:stream_error, _}, 5000
        end)

      assert log =~ "transport error"
      assert log =~ "message_count: 1"
      refute log =~ "sk-"
      refute log =~ "USER SECRET"
    end

    test "exception inside the rescue clause logs an error" do
      pid = self()

      log =
        capture_log(fn ->
          OpenAI.stream(["not a message map"], pid)
          assert_receive {:stream_error, _}, 1000
        end)

      assert log =~ "exception"
      assert log =~ "message_count: 1"
      refute log =~ "sk-"
      refute log =~ "not a message map"
    end
  end

  # ── Positive: single token ─────────────────────────────────────

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

  # ── Positive: tokens accumulate to correct full response ───────

  test "accumulated tokens form the correct full response", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)

      conn =
        Enum.reduce(["The ", "quick ", "brown ", "fox"], conn, fn word, conn ->
          {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk(word))
          conn
        end)

      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    # collect_tokens/2 drains :stream_token messages and returns when
    # it receives :stream_done — so :stream_done is already consumed.
    tokens = collect_tokens([], 5000)
    assert Enum.join(tokens) == "The quick brown fox"
  end

  # ── Positive: TCP chunk boundary split ─────────────────────────

  test "token split across TCP chunks is reassembled correctly", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      json = Jason.encode!(%{choices: [%{delta: %{content: "Split"}, finish_reason: nil}]})
      full_line = "data: #{json}"
      half = div(byte_size(full_line), 2)
      {:ok, conn} = Plug.Conn.chunk(conn, binary_part(full_line, 0, half))

      {:ok, conn} =
        Plug.Conn.chunk(conn, binary_part(full_line, half, byte_size(full_line) - half) <> "\n\n")

      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_token, "Split"}, 3000
    assert_receive :stream_done, 1000
  end

  # ── Positive: [DONE] does not produce a :stream_token ──────────

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

  # ── Negative: HTTP 401 (bad API key) → {:stream_error, _} ──────
  #
  # With the sprint-1.9 QA fix, ChatApp.OpenAI.stream/2 now inspects
  # response.status and sends {:stream_error, "HTTP N"} for any non-2xx
  # response instead of silently sending :stream_done with no tokens.
  test "HTTP 401 response sends {:stream_error, _}", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Invalid API key"}}))
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_error, "HTTP 401"}, 3000
    refute_receive {:stream_token, _}, 300
  end

  # ── Negative: HTTP 500 → {:stream_error, _} ────────────────────

  test "HTTP 500 response sends {:stream_error, _}", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.send_resp(conn, 500, Jason.encode!(%{error: %{message: "Internal server error"}}))
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_error, "HTTP 500"}, 3000
    refute_receive {:stream_token, _}, 300
  end

  # ── Negative: server closes connection abruptly ────────────────

  test "abrupt connection close does not crash the caller", %{bypass: bypass} do
    pid = self()

    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      # Send one chunk then forcibly close (Bypass closes after handler returns)
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("Partial"))
      conn
    end)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    # Drain any :stream_token messages that arrived before the close,
    # then assert the terminal message is :stream_done or {:stream_error, _}.
    terminal =
      receive do
        :stream_done = msg ->
          msg

        {:stream_error, _} = msg ->
          msg

        {:stream_token, _} ->
          receive do
            :stream_done = msg -> msg
            {:stream_error, _} = msg -> msg
          after
            3000 -> :timeout
          end
      after
        3000 -> :timeout
      end

    assert match?(:stream_done, terminal) or match?({:stream_error, _}, terminal)
  end

  # ── Negative: connection refused → {:stream_error, _} ──────────

  test "connection refused sends {:stream_error, _}", %{bypass: bypass} do
    pid = self()
    Bypass.down(bypass)

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_error, _}, 5000
  end

  # ── Negative: HTTP timeout → {:stream_error, _} ────────────────
  #
  # receive_timeout is configurable via :openai_receive_timeout so this test
  # can use a short timeout (200ms) without waiting 120 seconds.
  # Bypass holds the connection open for longer than the timeout, triggering
  # a Req.TransportError which routes to {:stream_error, _}.
  test "HTTP timeout sends {:stream_error, _}" do
    pid = self()

    # Start a raw TCP listener that accepts the connection then goes silent —
    # never sending any bytes. This lets Req's receive_timeout fire without
    # involving Bypass (whose handler lifetime is tied to Cowboy, causing
    # process-shutdown interference when Req drops the connection).
    {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_ip, port}} = :inet.sockname(listen_sock)

    Task.start(fn ->
      {:ok, _conn} = :gen_tcp.accept(listen_sock)
      # Hold the connection open: accept the TCP connection but send nothing.
      # The Task exits when the test process exits, closing the socket.
      Process.sleep(:infinity)
    end)

    # Short timeout (200ms) so the test doesn't wait 120 seconds.
    Application.put_env(:chat_app, :openai_receive_timeout, 200)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{port}/v1/chat/completions"
    )

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

    assert_receive {:stream_retrying, 0}, 2000
    assert_receive {:stream_retrying, 1}, 3000
    assert_receive {:stream_error, _}, 5000

    :gen_tcp.close(listen_sock)
  end

  # ── Real API smoke test (skipped in CI) ────────────────────────

  @tag :real_api
  test "real OpenAI API returns at least one token" do
    pid = self()
    messages = [%{role: :user, content: "Say exactly: pong"}]

    # Restore real URL for this test (overrides the Bypass URL set in setup)
    Application.put_env(:chat_app, :openai_api_url, "https://api.openai.com/v1/chat/completions")

    Task.start(fn -> OpenAI.stream(messages, pid) end)

    assert_receive {:stream_token, _token}, 15_000
    # Drain remaining tokens
    assert_receive :stream_done, 15_000
  end
end
