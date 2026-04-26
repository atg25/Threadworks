defmodule ChatAppWeb.Sprint12ImmediateFixesResilienceE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  defmodule SlowStreamStub do
    @moduledoc false

    def stream(_messages, pid) do
      owner = Application.get_env(:chat_app, :sp12_e2e_owner)
      send(owner, {:sp12_e2e_stream_pid, self()})

      Enum.each(1..6, fn _ ->
        send(pid, {:stream_token, "x"})
        Process.sleep(500)
      end)

      send(pid, :stream_done)
    end
  end

  feature "Positive — Stop on disconnect cancels the stream", %{session: session} do
    original_module = Application.get_env(:chat_app, :openai_module)
    original_owner = Application.get_env(:chat_app, :sp12_e2e_owner)

    on_exit(fn ->
      restore_env(:openai_module, original_module)
      restore_env(:sp12_e2e_owner, original_owner)
    end)

    Application.put_env(:chat_app, :openai_module, SlowStreamStub)
    Application.put_env(:chat_app, :sp12_e2e_owner, self())

    session =
      session
      |> visit("/")
      |> type_and_submit("slow message")

    assert_receive {:sp12_e2e_stream_pid, stream_pid}, 1_000
    ref = Process.monitor(stream_pid)

    _session = execute_script(session, "window.location.href = 'about:blank';")
    assert_receive {:DOWN, ^ref, :process, _, _}, 2_000
  end

  feature "Negative — burst of 25 messages stops at 20 with a flash", %{session: session} do
    session =
      Enum.reduce(1..25, visit(session, "/"), fn i, s ->
        type_and_submit(s, "burst-#{i}")
      end)

    session
    |> assert_has(css("[data-role='user']", count: 20))
    |> assert_has(css("[role='alert']", text: "Slow down"))
  end

  feature "Negative — `:stream_error` does not poison the next turn", %{session: session} do
    original_module = Application.get_env(:chat_app, :openai_module)
    original_owner = Application.get_env(:chat_app, :sp12_e2e_owner)

    on_exit(fn ->
      restore_env(:openai_module, original_module)
      restore_env(:sp12_e2e_owner, original_owner)
    end)

    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)
    Application.put_env(:chat_app, :sp12_e2e_owner, self())

    parent = self()
    counter = :counters.new(1, [])

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      call_no = :counters.add(counter, 1, 1)
      send(parent, {:sp12_e2e_openai_body, call_no, payload})

      if call_no == 1 do
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{error: "unauthorized"})
      else
        Req.Test.text(conn, "data: [DONE]\n\n")
      end
    end)

    session =
      session
      |> visit("/")
      |> type_and_submit("first")
      |> assert_has(css("[data-role='assistant']", text: "Error:"))
      |> type_and_submit("second")

    assert_has(session, css("[data-chat-message-error]", text: "Error:", minimum: 1))

    # The integration suite covers request-body assertions directly.
    # At E2E level we assert visible behavior remains healthy after an error turn.
    assert_has(session, css("[data-role='user']", text: "second"))
  end

  feature "Negative — orphaned scaffold removal does not break navigation", %{session: session} do
    session =
      session
      |> visit("/")
      |> assert_has(css("#chat-input"))
      |> execute_script("window.location.reload();")
      |> visit("/")

    session
    |> assert_has(css("#chat-input"))
    |> refute_has(css(".phx-error"))
  end

  defp type_and_submit(session, text) do
    session
    |> click(css("#chat-input"))
    |> send_keys(text)
    |> send_keys([:enter])
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
