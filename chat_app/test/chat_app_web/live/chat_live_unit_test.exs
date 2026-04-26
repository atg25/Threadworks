defmodule ChatAppWeb.ChatLiveUnitTest do
  use ExUnit.Case, async: true

  alias ChatApp.Chat

  describe "upsert_assistant_message/2" do
    test "appends assistant message when messages list ends with user role" do
      messages = [%{role: :user, content: "hello"}]
      result = Chat.upsert_assistant_message(messages, "Hi there")
      assert length(result) == 2
      assert List.last(result) == %{role: :assistant, content: "Hi there"}
    end

    test "updates last message when it is already an assistant message" do
      messages = [
        %{role: :user, content: "hello"},
        %{role: :assistant, content: "Hi"}
      ]

      result = Chat.upsert_assistant_message(messages, "Hi there!")
      assert length(result) == 2
      assert List.last(result) == %{role: :assistant, content: "Hi there!"}
    end

    test "appends assistant message to empty list" do
      result = Chat.upsert_assistant_message([], "First token")
      assert result == [%{role: :assistant, content: "First token"}]
    end

    test "does not grow list beyond expected length when updating assistant msg" do
      messages = [
        %{role: :user, content: "Q"},
        %{role: :assistant, content: "A"}
      ]

      result = Chat.upsert_assistant_message(messages, "A longer answer")
      assert length(result) == 2
    end

    test "never changes role of existing user message" do
      messages = [%{role: :user, content: "Q"}]
      result = Chat.upsert_assistant_message(messages, "A")
      user_msgs = Enum.filter(result, &(&1.role == :user))
      assert length(user_msgs) == 1
      assert hd(user_msgs).content == "Q"
    end
  end
end
