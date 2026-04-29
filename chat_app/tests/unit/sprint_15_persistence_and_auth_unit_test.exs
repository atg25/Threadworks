defmodule ChatApp.Sprint15PersistenceAndAuthUnitTest do
  use ExUnit.Case, async: false

  alias ChatApp.Conversations.{Conversation, Message}
  alias ChatApp.Repo

  test "Conversation.changeset/2 requires session_id" do
    changeset = Conversation.changeset(struct(Conversation), %{title: "x"})

    refute changeset.valid?
    assert {:session_id, {_, _}} = List.keyfind(changeset.errors, :session_id, 0)
  end

  test "Conversation.changeset/2 enforces unique session_id constraint at the schema layer" do
    first =
      struct(Conversation)
      |> Conversation.changeset(%{session_id: "abc"})
      |> Repo.insert()

    second =
      struct(Conversation)
      |> Conversation.changeset(%{session_id: "abc"})
      |> Repo.insert()

    assert {:ok, _} = first

    assert {:error, changeset} = second
    assert {:session_id, {_, opts}} = List.keyfind(changeset.errors, :session_id, 0)
    assert Keyword.get(opts, :constraint) == :unique
  end

  test "Message.changeset/2 rejects roles other than :user / :assistant" do
    changeset =
      Message.changeset(struct(Message), %{
        conversation_id: 1,
        role: :system,
        content: "x"
      })

    refute changeset.valid?
    assert {:role, {_, opts}} = List.keyfind(changeset.errors, :role, 0)
    assert Keyword.get(opts, :validation) == :inclusion
  end

  test "Message.changeset/2 requires content (non-empty string allowed)" do
    missing_content = Message.changeset(struct(Message), %{conversation_id: 1, role: :user})

    refute missing_content.valid?
    assert {:content, {_, _}} = List.keyfind(missing_content.errors, :content, 0)

    empty_string =
      Message.changeset(struct(Message), %{conversation_id: 1, role: :assistant, content: ""})

    assert empty_string.valid?
  end

  test "cents_to_dollars/1 formats to two decimals with leading $" do
    assert ChatApp.Chat.cents_to_dollars(0) == "$0.00"
    assert ChatApp.Chat.cents_to_dollars(7) == "$0.07"
    assert ChatApp.Chat.cents_to_dollars(1234) == "$12.34"
    assert ChatApp.Chat.cents_to_dollars(100_000) == "$1000.00"
  end

  test "auth_basic_when_configured/2 is a no-op when both env vars are unset" do
    Application.delete_env(:chat_app, :basic_auth_user)
    Application.delete_env(:chat_app, :basic_auth_password)

    conn = Plug.Test.conn(:get, "/")
    conn = ChatAppWeb.BasicAuth.auth_basic_when_configured(conn, [])

    refute conn.halted
    assert [] == Plug.Conn.get_resp_header(conn, "www-authenticate")
  end

  test "drop_last_assistant/1 removes only the trailing assistant entry" do
    assert ChatApp.Chat.drop_last_assistant([%{role: :user}, %{role: :assistant}]) == [%{role: :user}]
    assert ChatApp.Chat.drop_last_assistant([%{role: :user}]) == [%{role: :user}]
    assert ChatApp.Chat.drop_last_assistant([]) == []

    assert ChatApp.Chat.drop_last_assistant([
             %{role: :assistant},
             %{role: :user}
           ]) == [%{role: :assistant}, %{role: :user}]
  end
end
