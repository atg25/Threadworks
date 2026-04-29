defmodule ChatApp.OpenAIRetryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ChatApp.OpenAI

  setup do
    bypass = Bypass.open()

    original_module = Application.get_env(:chat_app, :openai_module)
    original_url = Application.get_env(:chat_app, :openai_api_url)
    original_req_opts = Application.get_env(:chat_app, :req_options)
    original_timeout = Application.get_env(:chat_app, :openai_receive_timeout)

    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

    Application.put_env(:chat_app, :req_options, [])
    Application.put_env(:chat_app, :openai_receive_timeout, 2000)

    on_exit(fn ->
      restore_env(:openai_module, original_module)
      restore_env(:openai_api_url, original_url)
      restore_env(:req_options, original_req_opts)
      restore_env(:openai_receive_timeout, original_timeout)
    end)

    {:ok, bypass: bypass}
  end

  defp sse_done, do: "data: [DONE]\n\n"

  defp sse_chunk(content) do
    json = Jason.encode!(%{choices: [%{delta: %{content: content}, finish_reason: nil}]})
    "data: #{json}\n\n"
  end

  # ---------------------------------------------------------------------------
  # TASK 6 — backoff_ms pure unit test
  # ---------------------------------------------------------------------------

  describe "backoff_ms/1" do
    test "backoff_ms increases between retries" do
      assert OpenAI.backoff_ms(0) == 250
      assert OpenAI.backoff_ms(1) == 500
      assert OpenAI.backoff_ms(2) == 1000
    end
  end

  # ---------------------------------------------------------------------------
  # TASK 6 — retry integration tests (Bypass)
  # ---------------------------------------------------------------------------

  describe "retry semantics" do
    test "transport error retries up to 2 times and succeeds on 3rd attempt", %{bypass: bypass} do
      pid = self()

      # Start down
      Bypass.down(bypass)

      log =
        capture_log(fn ->
          Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

          assert_receive {:stream_retrying, 0}, 3000
          assert_receive {:stream_retrying, 1}, 3000

          # Bring it up for the 3rd attempt
          Bypass.up(bypass)

          Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
            conn = Plug.Conn.send_chunked(conn, 200)
            {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("hello"))
            {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
            conn
          end)

          assert_receive :stream_done, 5000
        end)

      assert log =~ "retryable failure"
    end

    test "3rd transport error escalates to :stream_error", %{bypass: bypass} do
      pid = self()

      Bypass.down(bypass)

      Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

      assert_receive {:stream_retrying, 0}, 3000
      assert_receive {:stream_retrying, 1}, 3000
      assert_receive {:stream_error, _}, 5000
      refute_receive :stream_done, 500
    end

    test "4xx response does NOT retry", %{bypass: bypass} do
      pid = self()

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Unauthorized"}}))
      end)

      log =
        capture_log(fn ->
          Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)
          assert_receive {:stream_error, "HTTP 401"}, 3000
        end)

      refute log =~ "retryable failure"
      refute_receive {:stream_retrying, _}, 500
    end

    test "transport error retries and succeeds on recovery", %{bypass: bypass} do
      pid = self()

      # Keep it down for first attempt
      Bypass.down(bypass)

      Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

      assert_receive {:stream_retrying, 0}, 3000

      # Bring up for the second attempt
      Bypass.up(bypass)

      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn = Plug.Conn.send_chunked(conn, 200)
        {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("ok"))
        {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
        conn
      end)

      assert_receive :stream_done, 5000
    end

    test ":stream_retrying is sent before each retry attempt", %{bypass: bypass} do
      pid = self()

      Bypass.down(bypass)

      Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

      assert_receive {:stream_retrying, 0}, 3000
      assert_receive {:stream_retrying, 1}, 3000
      assert_receive {:stream_error, _}, 5000
    end
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
