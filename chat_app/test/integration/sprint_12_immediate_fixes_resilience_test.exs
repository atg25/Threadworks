defmodule ChatAppWeb.Sprint12ImmediateFixesResilienceIntegrationTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule StreamCallTracker do
    @moduledoc false

    def stream(_messages, pid) do
      owner = Application.get_env(:chat_app, :sp12_stream_tracker_owner)
      send(owner, :sp12_stream_called)
      send(pid, {:stream_token, ""})
    end
  end

  test "send_message stores the streaming task pid in assigns", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "hello")

    task_pid = live_assigns(view).stream_task_pid
    assert is_pid(task_pid)
    assert Process.alive?(task_pid)
  end

  test ":stream_done clears stream_task_pid to nil", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "hello")
    send(view.pid, :stream_done)

    assert live_assigns(view).stream_task_pid == nil
  end

  test ":stream_error clears stream_task_pid to nil and appends to :errors, NOT :messages", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "hello")
    send(view.pid, {:stream_error, "boom"})

    assigns = live_assigns(view)
    assert assigns.stream_task_pid == nil
    assert length(assigns.messages) == 1
    assert length(assigns.errors) == 1
    assert hd(assigns.errors).reason == "boom"
  end

  test "terminating the LiveView kills the streaming task", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "hello")

    task_pid = live_assigns(view).stream_task_pid
    ref = Process.monitor(task_pid)
    GenServer.stop(view.pid, :normal)

    assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
  end

  test "error renders in [data-chat-message-error] element", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "hello")
    send(view.pid, {:stream_error, "connection refused"})

    assert has_element?(view, "[data-chat-message-error]", "connection refused")
  end

  test "next send_message after a :stream_error does NOT include \"Error:\" in the OpenAI body",
       %{
         conn: conn
       } do
    original_module = Application.get_env(:chat_app, :openai_module)
    on_exit(fn -> restore_env(:openai_module, original_module) end)
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      send(parent, {:captured_body, payload})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    {:ok, view, _html} = live(conn, "/")
    submit_message(view, "first")
    send(view.pid, {:stream_error, "boom"})
    submit_message(view, "second")

    assert_receive {:captured_body, body}

    contents =
      body["messages"]
      |> Enum.map(&Map.get(&1, "content", ""))

    assert Enum.all?(contents, &(not String.contains?(&1, "Error:")))
  end

  test "21st send_message in 60s is rejected", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_many_messages(view, 21)

    assert length(live_assigns(view).messages) == 20
    assert render(view) =~ "Slow down"
  end

  test "rate-limited send does NOT invoke openai_module().stream/2", %{conn: conn} do
    original_module = Application.get_env(:chat_app, :openai_module)
    original_owner = Application.get_env(:chat_app, :sp12_stream_tracker_owner)

    on_exit(fn ->
      restore_env(:openai_module, original_module)
      restore_env(:sp12_stream_tracker_owner, original_owner)
    end)

    Application.put_env(:chat_app, :sp12_stream_tracker_owner, self())
    Application.put_env(:chat_app, :openai_module, StreamCallTracker)

    {:ok, view, _html} = live(conn, "/")
    send_many_messages(view, 21)

    call_count = receive_stream_calls(21, 0)
    assert call_count == 20
  end

  test "rate-limit flash contains the substring \"Slow down\"", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    send_many_messages(view, 21)

    html = render(view)
    assert html =~ "Slow down"
  end

  test "removed PageController route returns 404", %{conn: conn} do
    conn = get(conn, "/page")
    assert conn.status == 404
  end

  defp submit_message(view, message) do
    view
    |> element("form[data-chat-composer-form]")
    |> render_submit(%{"input" => message})
  end

  defp send_many_messages(view, count) do
    Enum.each(1..count, fn i ->
      submit_message(view, "msg-#{i}")
      send(view.pid, :stream_done)
    end)
  end

  defp live_assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)

  defp receive_stream_calls(remaining, count) when remaining <= 0, do: count

  defp receive_stream_calls(remaining, count) do
    receive do
      :sp12_stream_called ->
        receive_stream_calls(remaining - 1, count + 1)
    after
      100 -> count
    end
  end
end
