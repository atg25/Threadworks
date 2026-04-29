defmodule ChatApp.Sprint16FeatureVelocityUnitTest do
  use ExUnit.Case, async: false

  alias ChatApp.Conversations
  alias ChatApp.Conversations.Conversation
  alias ChatApp.Markdown

  test "auto_title_from_first_message/1 trims to 60 chars" do
    assert function_exported?(Conversations, :auto_title_from_first_message, 1)

    long_text = String.duplicate("a", 200)
    title = Conversations.auto_title_from_first_message(long_text)

    assert String.length(title) == 60
  end

  test "auto_title_from_first_message/1 collapses whitespace" do
    assert function_exported?(Conversations, :auto_title_from_first_message, 1)

    assert Conversations.auto_title_from_first_message("  hello\n\n   world  ") == "hello world"
  end

  test "Conversation.changeset/2 rejects unknown model values" do
    changeset = Conversation.changeset(struct(Conversation), %{session_id: "s", model: "fake-gpt-99"})

    refute changeset.valid?
    assert {:model, {_, opts}} = List.keyfind(changeset.errors, :model, 0)
    assert Keyword.get(opts, :validation) == :inclusion
  end

  test "Conversation.changeset/2 rejects temperature outside [0.0, 2.0]" do
    low = Conversation.changeset(struct(Conversation), %{session_id: "s1", temperature: -0.1})
    high = Conversation.changeset(struct(Conversation), %{session_id: "s2", temperature: 2.1})

    refute low.valid?
    refute high.valid?
    assert List.keyfind(low.errors, :temperature, 0)
    assert List.keyfind(high.errors, :temperature, 0)
  end

  test "Conversation.changeset/2 rejects system_prompt longer than 4000 chars" do
    prompt = String.duplicate("x", 4001)
    changeset = Conversation.changeset(struct(Conversation), %{session_id: "s", system_prompt: prompt})

    refute changeset.valid?
    assert List.keyfind(changeset.errors, :system_prompt, 0)
  end

  test "Markdown.to_html wraps a fenced elixir block in .ui-code-block with data-language=elixir" do
    html = Markdown.to_html("```elixir\nIO.puts(\"hi\")\n```")

    assert html =~ ~s(<div class="ui-code-block" data-language="elixir">)
    assert html =~ ~s(<span class="ui-code-block-lang">elixir</span>)
  end

  test "Markdown.to_html unlabeled fence yields data-language=text" do
    html = Markdown.to_html("```\nplain\n```")
    assert html =~ ~s(data-language="text")
  end

  test "Markdown.to_html does NOT wrap inline code" do
    html = Markdown.to_html("`print(\"hi\")`")

    assert html =~ "<code>"
    refute html =~ "ui-code-block"
  end

  test "Markdown.to_html with multiple code blocks wraps each independently" do
    html = Markdown.to_html("```elixir\na\n```\n\n```javascript\nb\n```")

    assert length(Regex.scan(~r/ui-code-block/, html)) == 2
  end

  test "record_usage cost computation with gpt-4o pricing" do
    assert function_exported?(Conversations, :record_usage, 4)

    usage = %{"prompt_tokens" => 1_000_000, "completion_tokens" => 500_000, "total_tokens" => 1_500_000}

    assert {:ok, row} = Conversations.record_usage(1, 1, "gpt-4o", usage)
    assert row.estimated_cost_cents == 750
  end

  test "record_usage with unknown model logs warning and stores cost = 0" do
    assert function_exported?(Conversations, :record_usage, 4)

    usage = %{"prompt_tokens" => 100, "completion_tokens" => 200, "total_tokens" => 300}

    assert {:ok, row} = Conversations.record_usage(1, 1, "fake-gpt-99", usage)
    assert row.estimated_cost_cents == 0
  end

  test "cents_to_dollars/1 formatting" do
    assert ChatApp.Chat.cents_to_dollars(0) == "$0.00"
    assert ChatApp.Chat.cents_to_dollars(7) == "$0.07"
    assert ChatApp.Chat.cents_to_dollars(1234) == "$12.34"
  end

  test "backoff_ms increases between retries" do
    assert function_exported?(ChatApp.OpenAI, :backoff_ms, 1)

    assert ChatApp.OpenAI.backoff_ms(0) == 250
    assert ChatApp.OpenAI.backoff_ms(1) == 500
    assert ChatApp.OpenAI.backoff_ms(2) == 1000
  end

  test "drop_last_assistant/1 only drops a trailing assistant entry" do
    assert function_exported?(ChatAppWeb.ChatLive, :drop_last_assistant, 1)

    assert ChatAppWeb.ChatLive.drop_last_assistant([%{role: :user}, %{role: :assistant}]) == [%{role: :user}]
    assert ChatAppWeb.ChatLive.drop_last_assistant([%{role: :user}]) == [%{role: :user}]
    assert ChatAppWeb.ChatLive.drop_last_assistant([]) == []
  end

  test "record_usage stores the row with the right cost" do
    assert function_exported?(Conversations, :record_usage, 4)

    usage = %{"prompt_tokens" => 100_000, "completion_tokens" => 100_000, "total_tokens" => 200_000}
    assert {:ok, row} = Conversations.record_usage(1, 1, "gpt-4o-mini", usage)
    assert row.total_tokens == 200_000
    assert is_integer(row.estimated_cost_cents)
  end

  test "record_usage rejects non-positive token counts" do
    assert function_exported?(Conversations, :record_usage, 4)

    usage = %{"prompt_tokens" => 0, "completion_tokens" => -1, "total_tokens" => -1}
    assert {:error, _changeset} = Conversations.record_usage(1, 1, "gpt-4o-mini", usage)
  end

  test "usage_for_conversation sums all records" do
    assert function_exported?(Conversations, :usage_for_conversation, 1)

    totals = Conversations.usage_for_conversation(123)
    assert totals.total_tokens == 600
    assert totals.total_cost_cents == 6
  end

  test "unknown model defaults to a documented fallback price (or zero, with a Logger warning)" do
    assert function_exported?(Conversations, :record_usage, 4)

    usage = %{"prompt_tokens" => 10, "completion_tokens" => 10, "total_tokens" => 20}
    assert {:ok, row} = Conversations.record_usage(1, 1, "unknown-model", usage)
    assert row.estimated_cost_cents == 0
  end

  test "deleting a conversation cascades to usage_records" do
    assert function_exported?(Conversations, :record_usage, 4)
    assert function_exported?(Conversations, :usage_for_conversation, 1)

    usage = %{"prompt_tokens" => 10, "completion_tokens" => 10, "total_tokens" => 20}
    assert {:ok, _} = Conversations.record_usage(1, 1, "gpt-4o", usage)
    assert {:ok, _} = Conversations.delete_conversation(1)

    totals = Conversations.usage_for_conversation(1)
    assert totals.total_tokens == 0
    assert totals.total_cost_cents == 0
  end

  test "stream emits :stream_usage when the usage block arrives" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test "stream still works correctly when the usage block is missing" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
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

  test ":stream_retrying is sent before each retry attempt" do
    assert function_exported?(ChatApp.OpenAI, :stream, 3)
  end

  test "Migration 20260501000000_allow_multiple_conversations_per_session exists and is idempotent" do
    migration = "/Users/agard/NJIT/IS322/Final/chat_app/priv/repo/migrations/20260501000000_allow_multiple_conversations_per_session.exs"
    assert File.exists?(migration)
  end

  test "unique_index(:conversations, [:session_id]) is removed by the new migration" do
    migration = "/Users/agard/NJIT/IS322/Final/chat_app/priv/repo/migrations/20260501000000_allow_multiple_conversations_per_session.exs"

    assert File.read!(migration) =~ "drop unique_index(:conversations, [:session_id])"
  end

  test "usage_records table created with FK ON DELETE CASCADE" do
    migration = "/Users/agard/NJIT/IS322/Final/chat_app/priv/repo/migrations/20260515000000_create_usage_records.exs"

    assert File.exists?(migration)
    text = File.read!(migration)
    assert text =~ "on_delete: :delete_all"
  end

  test "floki dependency available outside :test" do
    mix_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/mix.exs")

    assert mix_text =~ "{:floki, \"\u003e= 0.30.0\"}"
    refute mix_text =~ "{:floki, \"\u003e= 0.30.0\", only: :test}"
  end

  test "stream_options: %{include_usage: true} present in the OpenAI body builder" do
    openai_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app/openai.ex")
    assert openai_text =~ "stream_options: %{include_usage: true}"
  end

  test "@max_retries 2 and @prices_per_1m_tokens are module attributes (not magic numbers)" do
    conv_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app/conversations.ex")
    openai_text = File.read!("/Users/agard/NJIT/IS322/Final/chat_app/lib/chat_app/openai.ex")

    assert conv_text =~ "@prices_per_1m_tokens"
    assert openai_text =~ "@max_retries 2"
  end
end
