defmodule ChatApp.OpenAITest do
  # async: false — modifies global Application env
  use ExUnit.Case, async: false

  alias ChatApp.OpenAI

  describe "req_options merge" do
    test "req_options can override receive_timeout" do
      pid = self()

      original_req_opts = Application.get_env(:chat_app, :req_options)
      original_url = Application.get_env(:chat_app, :openai_api_url)

      on_exit(fn ->
        restore_env(:req_options, original_req_opts)
        restore_env(:openai_api_url, original_url)
      end)

      # Start a raw TCP listener that accepts the connection then goes silent.
      {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, {_ip, port}} = :inet.sockname(listen_sock)

      Task.start(fn ->
        {:ok, _conn} = :gen_tcp.accept(listen_sock)
        Process.sleep(:infinity)
      end)

      Application.put_env(
        :chat_app,
        :openai_api_url,
        "http://localhost:#{port}/v1/chat/completions"
      )

      # Override receive_timeout via req_options. This intentionally replaces
      # the test config's Req.Test plug, so this call uses the real adapter.
      Application.put_env(:chat_app, :req_options, receive_timeout: 50)

      Task.start(fn -> OpenAI.stream([%{role: :user, content: "Q"}], pid) end)

      assert_receive {:stream_retrying, 0}, 1000
      assert_receive {:stream_retrying, 1}, 1500
      assert_receive {:stream_error, _}, 3000

      :gen_tcp.close(listen_sock)
    end
  end

  # Positive: stream/2 sends {:stream_error, reason} on transport error (no real network call).
  test "stream/2 sends {:stream_error, reason} when connection is refused" do
    pid = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], pid)

    assert_received {:stream_error, _reason}
  end

  # Negative: stream/2 sends {:stream_error, reason} when api_key is not set.
  test "stream/2 sends {:stream_error, reason} when api_key is missing" do
    pid = self()

    original = Application.get_env(:chat_app, :openai_api_key)
    Application.delete_env(:chat_app, :openai_api_key)

    on_exit(fn ->
      if original, do: Application.put_env(:chat_app, :openai_api_key, original)
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], pid)

    assert_received {:stream_error, _reason}
  end

  test "stream/2 sends the configured :openai_model in the request body" do
    original_model = Application.get_env(:chat_app, :openai_model)
    on_exit(fn -> restore_env(:openai_model, original_model) end)
    Application.put_env(:chat_app, :openai_model, "gpt-test-12345")

    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:captured_model, Jason.decode!(body)["model"]})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], self())

    assert_received {:captured_model, "gpt-test-12345"}
  end

  test "stream/3 includes system_prompt as first message with role: system" do
    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      send(parent, {:captured_messages, decoded["messages"]})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    OpenAI.stream(
      [%{role: :user, content: "hello"}],
      self(),
      %{system_prompt: "Be terse."}
    )

    assert_received {:captured_messages, messages}
    assert [%{"role" => "system", "content" => "Be terse."} | _rest] = messages
  end

  test "stream/3 includes temperature in request body when provided" do
    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)
      send(parent, {:captured_temperature, decoded["temperature"]})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    OpenAI.stream(
      [%{role: :user, content: "hello"}],
      self(),
      %{temperature: 0.4}
    )

    assert_received {:captured_temperature, 0.4}
  end

  # ---------------------------------------------------------------------------
  # TASK 5 — :stream_usage emission tests
  # ---------------------------------------------------------------------------

  test "stream emits :stream_usage when the usage block arrives" do
    parent = self()

    # SSE response includes a usage chunk followed by [DONE]
    usage_chunk =
      ~s(data: {"choices":[{"delta":{"content":""}}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}\n\n)

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      Req.Test.text(conn, usage_chunk <> "data: [DONE]\n\n")
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], parent)

    assert_received {:stream_usage,
                     %{"prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15}}
  end

  test "stream still works correctly when the usage block is missing" do
    parent = self()

    # Normal SSE response without usage block
    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      Req.Test.text(
        conn,
        ~s(data: {"choices":[{"delta":{"content":"hello"}}]}\n\n) <> "data: [DONE]\n\n"
      )
    end)

    OpenAI.stream([%{role: :user, content: "Q"}], parent)

    assert_received {:stream_token, "hello"}
    assert_received :stream_done
    refute_received {:stream_usage, _}
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
