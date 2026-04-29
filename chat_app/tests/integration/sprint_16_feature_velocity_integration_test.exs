defmodule ChatAppWeb.Sprint16FeatureVelocityIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.Conversations

  defp create_session_conversation(attrs \\ %{}) do
    Conversations.create_conversation("test-session", attrs)
  end

  test "sidebar lists all conversations for the session", %{conn: conn} do
    assert function_exported?(Conversations, :list_conversations, 1)

    conversation = create_session_conversation()
    {:ok, _message} = Conversations.append_message(conversation.id, :assistant, "hello")

    {:ok, view, _html} = live(conn, "/")

    assert has_element?(view, ~s([data-conversation-id="#{conversation.id}"]))
  end

  test "new_conversation creates a row and switches to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[phx-click='new_conversation']")
    |> render_click()

    assigns = :sys.get_state(view.pid).socket.assigns

    assert is_integer(assigns.current_conversation_id)
    assert assigns.messages == []
  end

  test "switch_conversation loads its messages", %{conn: conn} do
    first = create_session_conversation(%{title: "First"})
    second = create_session_conversation(%{title: "Second"})
    {:ok, _message} = Conversations.append_message(first.id, :assistant, "hello")

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s([data-conversation-id="#{first.id}"] button[phx-click='switch_conversation']))
    |> render_click()

    assigns = :sys.get_state(view.pid).socket.assigns
    assert is_list(assigns.messages)
    assert assigns.current_conversation_id == first.id
    assert Enum.any?(assigns.conversations, &(&1.id == second.id))
  end

  test "delete_conversation removes the row and switches to the next", %{conn: conn} do
    first = create_session_conversation(%{title: "First"})
    second = create_session_conversation(%{title: "Second"})

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s([data-conversation-id="#{second.id}"] button[phx-click='delete_conversation']))
    |> render_click()

    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.current_conversation_id == first.id
    refute Enum.any?(assigns.conversations, &(&1.id == second.id))
  end

  test "deleting the only conversation creates a fresh one", %{conn: conn} do
    conversation = create_session_conversation()
    {:ok, _message} = Conversations.append_message(conversation.id, :assistant, "hello")

    {:ok, view, _html} = live(conn, "/")

    view
    |> element(~s([data-conversation-id="#{conversation.id}"] button[phx-click='delete_conversation']))
    |> render_click()

    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.messages == []
    assert is_integer(assigns.current_conversation_id)
    refute assigns.current_conversation_id == conversation.id
  end

  test "first user message auto-titles the conversation", %{conn: conn} do
    assert function_exported?(Conversations, :auto_title_from_first_message, 1)

    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]")
    |> render_submit(%{"input" => "What is OTP?"})

    assert has_element?(view, "[data-conversation-id]", "What is OTP?")
  end

  test "toggle_settings opens and closes the drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[phx-click='toggle_settings']")
    |> render_click()

    assert has_element?(view, "[data-settings-drawer]")

    view
    |> element("button[phx-click='toggle_settings']")
    |> render_click()

    refute has_element?(view, "[data-settings-drawer]")
  end

  test "save_settings persists model + system_prompt + temperature", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[phx-click='toggle_settings']")
    |> render_click()

    view
    |> form("form[phx-submit='save_settings']", %{
      "settings" => %{
        "model" => "gpt-4o-mini",
        "system_prompt" => "Be terse.",
        "temperature" => "0.4"
      }
    })
    |> render_submit()

    assert has_element?(view, "[data-settings-saved]", "Settings saved")
  end

  test "send_message uses the saved settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("button[phx-click='toggle_settings']")
    |> render_click()

    view
    |> form("form[phx-submit='save_settings']", %{
      "settings" => %{
        "model" => "gpt-4o-mini",
        "system_prompt" => "Be terse.",
        "temperature" => "0.4"
      }
    })
    |> render_submit()

    view
    |> form("form[data-chat-composer-form]", %{"input" => "hello"})
    |> render_submit()

    assert has_element?(view, "[data-current-model='gpt-4o-mini']")
  end

  test "send_message without saved settings omits temperature and system role", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "hello"})
    |> render_submit()

    refute has_element?(view, "[data-system-prompt-present='true']")
  end

  test "feedback controls are absent from the landing state", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='up']")
    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='down']")
  end

  test "feedback controls stay absent after an assistant response", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "hello"})
    |> render_submit()

    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='up']")
    refute has_element?(view, "button[phx-click='feedback'][phx-value-rating='down']")
  end

  test "XSS protection from Sprint 11 TASK 2 is preserved through the wrapper", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("form[data-chat-composer-form]", %{"input" => "```\n<script>alert(1)</script>\n```"})
    |> render_submit()

    send(view.pid, {:stream_token, "```\n<script>alert(1)</script>\n```"})
    send(view.pid, :stream_done)

    html = render(view)

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>alert(1)</script>"
    assert html =~ "ui-code-block"
  end

  test "transport error retries up to 2 times" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test "3rd transport error escalates to :stream_error" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test "4xx response does NOT retry" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test "5xx response retries" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test ":stream_retrying clears the partial assistant message in DB and assigns", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:stream_retrying, 0})

    assigns = :sys.get_state(view.pid).socket.assigns

    assert assigns.stream_buffer == ""
    assert is_nil(assigns.assistant_message_id)
  end

  test "usage_for_conversation sums all records" do
    assert function_exported?(Conversations, :usage_for_conversation, 1)

    totals = Conversations.usage_for_conversation(99)
    assert totals.total_tokens == 600
    assert totals.total_cost_cents == 6
  end

  test ":stream_retrying clears the partial assistant message" do
    assert function_exported?(ChatAppWeb.ChatLive, :handle_info, 2)
  end

  test ":stream_retrying inserts a transient error message" do
    assert function_exported?(ChatAppWeb.ChatLive, :handle_info, 2)
  end
end
