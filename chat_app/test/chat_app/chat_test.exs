defmodule ChatApp.ChatTest do
  use ExUnit.Case, async: true

  alias ChatApp.Chat

  describe "upsert_assistant_message/2" do
    test "upsert into empty list creates a new assistant message" do
      assert Chat.upsert_assistant_message([], "x") == [%{role: :assistant, content: "x"}]
    end

    test "upsert when last is :user appends a new assistant message" do
      messages = [%{role: :user, content: "Q"}]
      updated = Chat.upsert_assistant_message(messages, "first")

      assert length(updated) == 2
      assert Enum.at(updated, 0) == %{role: :user, content: "Q"}
      assert List.last(updated) == %{role: :assistant, content: "first"}
    end

    test "upsert when last is :assistant replaces the last message" do
      assert Chat.upsert_assistant_message([%{role: :assistant, content: "old"}], "new") == [
               %{role: :assistant, content: "new"}
             ]
    end

    test "upsert preserves all prior messages" do
      messages = [
        %{role: :user, content: "Q1"},
        %{role: :assistant, content: "A1"},
        %{role: :user, content: "Q2"},
        %{role: :assistant, content: "A2"},
        %{role: :user, content: "Q3"},
        %{role: :assistant, content: "A3"}
      ]

      updated = Chat.upsert_assistant_message(messages, "A3-new")
      assert length(updated) == length(messages)
      assert Enum.take(updated, length(updated) - 1) == Enum.take(messages, length(messages) - 1)
      assert List.last(updated) == %{role: :assistant, content: "A3-new"}

      updated2 = Chat.upsert_assistant_message(Enum.drop(messages, -1), "A3")
      assert length(updated2) == length(messages)
      assert List.last(updated2) == %{role: :assistant, content: "A3"}
    end

    test "upsert raises on non-list messages" do
      assert_raise FunctionClauseError, fn ->
        Chat.upsert_assistant_message("not a list", "x")
      end
    end

    test "upsert raises on non-binary buffer" do
      assert_raise FunctionClauseError, fn ->
        Chat.upsert_assistant_message([], 42)
      end
    end
  end
end
