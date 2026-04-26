defmodule ChatAppWeb.Sprint13HardeningArchitectureIntegrationTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ChatApp.OpenAI

  setup do
    bypass = Bypass.open()

    original_url = Application.get_env(:chat_app, :openai_api_url)
    original_req_opts = Application.get_env(:chat_app, :req_options)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

    Application.put_env(:chat_app, :req_options, [])

    on_exit(fn ->
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
    end)

    {:ok, bypass: bypass}
  end

  defp sse_chunk(content) do
    json =
      Jason.encode!(%{
        choices: [%{delta: %{content: content}, finish_reason: nil}]
      })

    "data: #{json}\n\n"
  end

  defp sse_done, do: "data: [DONE]\n\n"

  test "calling stream/2 twice from the same process does not leak buffers between calls", %{
    bypass: bypass
  } do
    pid = self()

    partial_json =
      Jason.encode!(%{
        choices: [%{delta: %{content: "first-call-token"}, finish_reason: nil}]
      })

    # First call leaves an unterminated SSE line in the parser buffer.
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, "data: " <> partial_json)
      conn
    end)

    OpenAI.stream([%{role: :user, content: "first"}], pid)
    assert_receive :stream_done, 3000
    refute_receive {:stream_token, _}, 200

    # Second call should start with a clean buffer and parse token normally.
    Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
      conn = Plug.Conn.send_chunked(conn, 200)
      {:ok, conn} = Plug.Conn.chunk(conn, sse_chunk("second-call-token"))
      {:ok, conn} = Plug.Conn.chunk(conn, sse_done())
      conn
    end)

    OpenAI.stream([%{role: :user, content: "second"}], pid)
    assert_receive {:stream_token, "second-call-token"}, 3000
    assert_receive :stream_done, 3000
  end

  test "req_options can override receive_timeout" do
    pid = self()

    # Start a raw TCP listener that accepts the connection then goes silent.
    {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, {_ip, port}} = :inet.sockname(listen_sock)

    Task.start(fn ->
      {:ok, _conn} = :gen_tcp.accept(listen_sock)
      Process.sleep(:infinity)
    end)

    Application.put_env(:chat_app, :req_options, receive_timeout: 50)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{port}/v1/chat/completions"
    )

    Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)
    assert_receive {:stream_error, _}, 1000

    :gen_tcp.close(listen_sock)
  end

  test "non-2xx logs a warning with status and message_count" do
    pid = self()

    Bypass.expect_once(bypass = Bypass.open(), "POST", "/v1/chat/completions", fn conn ->
      Plug.Conn.send_resp(conn, 401, Jason.encode!(%{error: %{message: "Invalid API key"}}))
    end)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

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

  test "transport error logs an error with reason and message_count" do
    pid = self()
    bypass = Bypass.open()
    Bypass.down(bypass)

    Application.put_env(
      :chat_app,
      :openai_api_url,
      "http://localhost:#{bypass.port}/v1/chat/completions"
    )

    log =
      capture_log(fn ->
        OpenAI.stream([%{role: :user, content: "USER SECRET"}], pid)
        assert_receive {:stream_error, _}, 5000
      end)

    assert log =~ "transport error"
    assert log =~ "reason:"
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

  test "dev boot raises an instructive error when no .env and no OPENAI_API_KEY" do
    _ = File.rm(".env")

    {output, status} =
      System.cmd(
        "env",
        [
          "-u",
          "OPENAI_API_KEY",
          "MIX_ENV=dev",
          "mix",
          "run",
          "-e",
          "IO.puts(\"booted\")"
        ],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "cp .env.example .env"
  end
end
