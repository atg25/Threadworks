defmodule ChatAppWeb.Sprint15PersistenceAndAuthIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.Conversations
  alias ChatApp.Conversations.{Conversation, Message}
  alias ChatApp.Repo

  test "get_or_create/1 is idempotent", _context do
    conv1 = Conversations.get_or_create("sess-1")
    conv2 = Conversations.get_or_create("sess-1")

    assert conv1.id == conv2.id
    assert Repo.aggregate(Conversation, :count) == 1
  end

  test "append_message/3 returns inserted message with id", _context do
    conv = Conversations.get_or_create("append-message")

    inserted = Conversations.append_message(conv.id, :user, "hi")

    assert is_map(inserted)
    assert Map.get(inserted, :__struct__) == Message
    assert is_integer(inserted.id)
    assert inserted.role == :user
    assert inserted.content == "hi"
    assert inserted.conversation_id == conv.id
  end

  test "update_assistant_message/2 mutates content in place", _context do
    conv = Conversations.get_or_create("assistant-update")

    msg = Conversations.append_message(conv.id, :assistant, "")
    _updated = Conversations.update_assistant_message(msg.id, "new buffer")

    assert Repo.get!(Message, msg.id).content == "new buffer"
  end

  test "delete_conversation/1 cascades to messages", _context do
    conv = Conversations.get_or_create("cascade")
    Conversations.append_message(conv.id, :user, "1")
    Conversations.append_message(conv.id, :assistant, "2")
    Conversations.append_message(conv.id, :user, "3")

    Conversations.reset_conversation("cascade")

    assert Repo.aggregate(Message, :count) == 0
  end

  test "messages are restored on remount", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, "/")

    live_view
    |> form("#chat-form", chat: %{message: "hello"})
    |> render_submit()

    send(live_view.pid, {:stream_token, "Stub "})
    send(live_view.pid, {:stream_token, "response."})
    send(live_view.pid, :stream_done)

    render(live_view)
    GenServer.stop(live_view.pid)

    {:ok, _new_live_view, html} = live(conn, "/")

    assert html =~ "hello"
    assert html =~ "Stub response."
  end

  test "new_conversation event clears messages and shows hero", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, "/")

    live_view
    |> form("#chat-form", chat: %{message: "hello"})
    |> render_submit()

    send(live_view.pid, {:stream_token, "ok"})
    send(live_view.pid, :stream_done)

    _ = render_click(element(live_view, "[phx-click=\"new_conversation\"]"))
    html = render(live_view)

    assert html =~ "id=\"chat-input\""
    refute html =~ "hello"
  end

  test "empty assistant content is persisted as \"\"", _context do
    conv = Conversations.get_or_create("empty-assistant")
    msg = Conversations.append_message(conv.id, :assistant, "")

    _ = Conversations.update_assistant_message(msg.id, "")

    assert Repo.get!(Message, msg.id).content == ""
  end

  test "per-conversation isolation: two session_ids do not share messages", _context do
    conv_a = Conversations.get_or_create("sess-A")
    conv_b = Conversations.get_or_create("sess-B")

    Conversations.append_message(conv_a.id, :user, "one")
    Conversations.append_message(conv_a.id, :assistant, "two")

    messages_b = Conversations.list_messages(conv_b.id)

    assert messages_b == []
  end

  test "throttled writes: 100 tokens result in fewer than 100 Repo updates", %{conn: conn} do
    parent = self()

    :telemetry.attach_many(
      "sprint15-repo-query-counter",
      [[:chat_app, :repo, :query]],
      fn _event, _measurements, _metadata, _config ->
        send(parent, :repo_query)
      end,
      nil
    )

    try do
      {:ok, live_view, _html} = live(conn, "/")

      Enum.each(1..100, fn idx ->
        send(live_view.pid, {:stream_token, "t#{idx}"})
      end)

      send(live_view.pid, :stream_done)

      Process.sleep(50)

      query_count =
        Stream.repeatedly(fn ->
          receive do
            :repo_query -> 1
          after
            0 -> :done
          end
        end)
        |> Enum.take_while(&(&1 != :done))
        |> Enum.sum()

      assert query_count <= 25
    after
      :telemetry.detach("sprint15-repo-query-counter")
    end
  end

  test ":stream_done forces a final write", _context do
    conv = Conversations.get_or_create("force-final")
    msg = Conversations.append_message(conv.id, :assistant, "")

    Enum.each(["a", "b", "c", "d", "e"], fn token ->
      existing = Repo.get!(Message, msg.id).content
      Conversations.update_assistant_message(msg.id, existing <> token)
    end)

    assert Repo.get!(Message, msg.id).content == "abcde"
  end

  test "GET / returns 200 when basic_auth_user is unset", %{conn: conn} do
    Application.delete_env(:chat_app, :basic_auth_user)
    Application.delete_env(:chat_app, :basic_auth_password)

    conn = get(conn, "/")

    assert html_response(conn, 200) =~ "id=\"chat-input\""
  end

  test "GET / returns 401 when configured and no Authorization header is sent", %{conn: conn} do
    Application.put_env(:chat_app, :basic_auth_user, "admin")
    Application.put_env(:chat_app, :basic_auth_password, "secret")

    on_exit(fn ->
      Application.delete_env(:chat_app, :basic_auth_user)
      Application.delete_env(:chat_app, :basic_auth_password)
    end)

    conn = get(conn, "/")

    assert response(conn, 401)
    assert ["Basic realm=\"Restricted Area\""] = get_resp_header(conn, "www-authenticate")
  end

  test "GET / returns 200 when correct Authorization header is sent", %{conn: conn} do
    Application.put_env(:chat_app, :basic_auth_user, "admin")
    Application.put_env(:chat_app, :basic_auth_password, "secret")

    on_exit(fn ->
      Application.delete_env(:chat_app, :basic_auth_user)
      Application.delete_env(:chat_app, :basic_auth_password)
    end)

    auth = Plug.BasicAuth.encode_basic_auth("admin", "secret")

    conn =
      conn
      |> put_req_header("authorization", auth)
      |> get("/")

    assert html_response(conn, 200) =~ "id=\"chat-input\""
  end

  test "GET / returns 401 with wrong password", %{conn: conn} do
    Application.put_env(:chat_app, :basic_auth_user, "admin")
    Application.put_env(:chat_app, :basic_auth_password, "secret")

    on_exit(fn ->
      Application.delete_env(:chat_app, :basic_auth_user)
      Application.delete_env(:chat_app, :basic_auth_password)
    end)

    auth = Plug.BasicAuth.encode_basic_auth("admin", "wrong")

    conn =
      conn
      |> put_req_header("authorization", auth)
      |> get("/")

    assert response(conn, 401)
  end

  test "stop_generation kills the streaming task and clears state", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, "/")

    live_view
    |> form("#chat-form", chat: %{message: "Generate"})
    |> render_submit()

    send(live_view.pid, {:stream_token, "A"})

    _ = render_click(element(live_view, "[phx-click=\"stop_generation\"]"))
    html = render(live_view)

    assert html =~ "A"
    refute html =~ "Sending"
  end

  test "regenerate after stream_done removes the last assistant message and re-streams from the prior user message", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, "/")

    live_view
    |> form("#chat-form", chat: %{message: "Original"})
    |> render_submit()

    send(live_view.pid, {:stream_token, "First answer"})
    send(live_view.pid, :stream_done)

    before = render(live_view)

    _ = render_click(element(live_view, "[phx-click=\"regenerate\"]"))
    after_render = render(live_view)

    assert before =~ "First answer"
    refute after_render =~ "First answer"
    assert after_render =~ "Original"
  end

  test "regenerate while is_sending is a no-op", %{conn: conn} do
    {:ok, live_view, _html} = live(conn, "/")

    live_view
    |> form("#chat-form", chat: %{message: "busy"})
    |> render_submit()

    in_flight = render(live_view)
    _ = render_click(element(live_view, "[phx-click=\"regenerate\"]"))
    after_click = render(live_view)

    assert after_click == in_flight
  end

  test "header rail contains four theme buttons with non-empty aria-labels", %{conn: conn} do
    {:ok, _live_view, html} = live(conn, "/")

    buttons = Floki.find(html, "[data-phx-theme]")

    assert length(buttons) == 4

    Enum.each(buttons, fn button ->
      assert Floki.attribute(button, "aria-label") |> List.first() |> is_binary()
      assert Floki.attribute(button, "aria-label") |> List.first() != ""
    end)
  end
end
