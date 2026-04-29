defmodule ChatApp.ConversationsTest do
  use ChatApp.DataCase, async: false

  alias ChatApp.Conversations
  alias ChatApp.Conversations.Conversation

  # ---------------------------------------------------------------------------
  # TASK 2 — Changeset validation unit tests
  # ---------------------------------------------------------------------------

  describe "Conversation.changeset/2 model validation" do
    test "accepts a known model value" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{model: "gpt-4o"})
      assert cs.valid?
    end

    test "rejects unknown model values" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{model: "fake-gpt-99"})
      refute cs.valid?

      assert {:model, {_msg, meta}} = List.keyfind(cs.errors, :model, 0)
      assert Keyword.get(meta, :validation) == :inclusion
    end

    test "allows nil model (nullable)" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{model: nil})
      assert cs.valid?
    end
  end

  describe "Conversation.changeset/2 temperature validation" do
    test "accepts temperature 0.0" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{temperature: 0.0})
      assert cs.valid?
    end

    test "accepts temperature 2.0" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{temperature: 2.0})
      assert cs.valid?
    end

    test "rejects temperature below 0.0" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{temperature: -0.1})
      refute cs.valid?

      assert {:temperature, {_msg, meta}} = List.keyfind(cs.errors, :temperature, 0)
      assert Keyword.get(meta, :validation) == :number
      assert Keyword.get(meta, :kind) == :greater_than_or_equal_to
    end

    test "rejects temperature above 2.0" do
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{temperature: 2.1})
      refute cs.valid?

      assert {:temperature, {_msg, meta}} = List.keyfind(cs.errors, :temperature, 0)
      assert Keyword.get(meta, :validation) == :number
      assert Keyword.get(meta, :kind) == :less_than_or_equal_to
    end
  end

  describe "Conversation.changeset/2 system_prompt validation" do
    test "accepts system_prompt up to 4000 chars" do
      prompt = String.duplicate("a", 4000)
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{system_prompt: prompt})
      assert cs.valid?
    end

    test "rejects system_prompt longer than 4000 chars" do
      prompt = String.duplicate("a", 4001)
      cs = Conversation.changeset(%Conversation{session_id: "s"}, %{system_prompt: prompt})
      refute cs.valid?

      assert {:system_prompt, {_msg, meta}} = List.keyfind(cs.errors, :system_prompt, 0)
      assert Keyword.get(meta, :validation) == :length
    end
  end

  # ---------------------------------------------------------------------------
  # TASK 2 — update_conversation_settings/2 integration tests (require DB)
  # ---------------------------------------------------------------------------

  describe "update_conversation_settings/2" do
    setup do
      conv = Conversations.create_conversation("session-settings-test", %{})
      {:ok, conv: conv}
    end

    test "persists model", %{conv: conv} do
      {:ok, updated} =
        Conversations.update_conversation_settings(conv.id, %{model: "gpt-4o-mini"})

      assert updated.model == "gpt-4o-mini"
      assert Conversations.get_conversation!(conv.id).model == "gpt-4o-mini"
    end

    test "persists system_prompt", %{conv: conv} do
      {:ok, updated} =
        Conversations.update_conversation_settings(conv.id, %{system_prompt: "Be terse."})

      assert updated.system_prompt == "Be terse."
    end

    test "persists temperature", %{conv: conv} do
      {:ok, updated} =
        Conversations.update_conversation_settings(conv.id, %{temperature: 0.4})

      assert updated.temperature == 0.4
    end

    test "returns {:error, changeset} on invalid model", %{conv: conv} do
      assert {:error, changeset} =
               Conversations.update_conversation_settings(conv.id, %{model: "not-a-real-model"})

      refute changeset.valid?
      assert {:model, {_msg, _meta}} = List.keyfind(changeset.errors, :model, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # TASK 5 — Usage record tests
  # ---------------------------------------------------------------------------

  describe "record_usage/4 cost computation" do
    setup do
      conv = Conversations.create_conversation("session-usage-test", %{})
      {:ok, msg} = Conversations.append_message(conv.id, :user, "Q")
      {:ok, conv: conv, msg: msg}
    end

    test "stores the row with gpt-4o pricing", %{conv: conv, msg: msg} do
      usage = %{
        "prompt_tokens" => 1_000_000,
        "completion_tokens" => 500_000,
        "total_tokens" => 1_500_000
      }

      result = Conversations.record_usage(conv.id, msg.id, "gpt-4o", usage)
      assert {:ok, record} = result

      # prompt: 1_000_000 * 250 / 1_000_000 = 250
      # completion: 500_000 * 1000 / 1_000_000 = 500
      # total: 750
      assert record.estimated_cost_cents == 750
      assert record.prompt_tokens == 1_000_000
      assert record.completion_tokens == 500_000
    end

    test "rejects non-positive prompt_tokens", %{conv: conv, msg: msg} do
      usage = %{
        "prompt_tokens" => 0,
        "completion_tokens" => 100,
        "total_tokens" => 100
      }

      assert {:error, _changeset} = Conversations.record_usage(conv.id, msg.id, "gpt-4o", usage)
    end

    test "unknown model logs warning and stores cost = 0", %{conv: conv, msg: msg} do
      usage = %{
        "prompt_tokens" => 100,
        "completion_tokens" => 100,
        "total_tokens" => 200
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          result = Conversations.record_usage(conv.id, msg.id, "fake-gpt-99", usage)
          assert {:ok, record} = result
          assert record.estimated_cost_cents == 0
        end)

      assert log =~ "unknown model"
    end
  end

  describe "usage_for_conversation/1" do
    setup do
      conv = Conversations.create_conversation("session-usage-agg-test", %{})
      {:ok, conv: conv}
    end

    test "sums all usage records", %{conv: conv} do
      # Insert 3 messages with usage manually by calling record_usage 3 times
      {:ok, m1} = Conversations.append_message(conv.id, :user, "Q1")
      {:ok, m2} = Conversations.append_message(conv.id, :user, "Q2")
      {:ok, m3} = Conversations.append_message(conv.id, :user, "Q3")

      Conversations.record_usage(conv.id, m1.id, "gpt-4o-mini", %{
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      })

      Conversations.record_usage(conv.id, m2.id, "gpt-4o-mini", %{
        "prompt_tokens" => 200,
        "completion_tokens" => 50,
        "total_tokens" => 250
      })

      Conversations.record_usage(conv.id, m3.id, "gpt-4o-mini", %{
        "prompt_tokens" => 300,
        "completion_tokens" => 50,
        "total_tokens" => 350
      })

      totals = Conversations.usage_for_conversation(conv.id)
      assert totals.total_tokens == 750
    end
  end

  # ---------------------------------------------------------------------------
  # TASK 5 — cents_to_dollars/1 formatting
  # ---------------------------------------------------------------------------

  describe "Chat.cents_to_dollars/1" do
    test "formats 0 cents as $0.00" do
      assert ChatApp.Chat.cents_to_dollars(0) == "$0.00"
    end

    test "formats 7 cents as $0.07" do
      assert ChatApp.Chat.cents_to_dollars(7) == "$0.07"
    end

    test "formats 1234 cents as $12.34" do
      assert ChatApp.Chat.cents_to_dollars(1234) == "$12.34"
    end
  end
end
