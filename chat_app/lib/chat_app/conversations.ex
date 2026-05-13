defmodule ChatApp.Conversations do
  @moduledoc """
  Persistence boundary for conversations and messages.
  """

  import Ecto.Query

  alias ChatApp.Conversations.{Conversation, Message, UsageRecord}
  alias ChatApp.Repo

  require Logger

  @conversation_insert_retry_attempts 3
  @conversation_insert_retry_backoff_ms 25

  @prices_per_1m_tokens %{
    "gpt-4o" => %{prompt: 250, completion: 1000},
    "gpt-4o-mini" => %{prompt: 15, completion: 60},
    "gpt-4.1" => %{prompt: 200, completion: 800},
    "gpt-4.1-mini" => %{prompt: 40, completion: 160}
  }

  def get_by_session(session_id) when is_binary(session_id) do
    Conversation
    |> where(session_id: ^session_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  def get_or_create(session_id) when is_binary(session_id), do: get_or_create_active(session_id)

  def get_or_create_active(session_id) when is_binary(session_id) do
    case list_conversations(session_id) do
      [] -> create_conversation(session_id, %{})
      [latest | _] -> latest
    end
  end

  def list_conversations(session_id) when is_binary(session_id) do
    Conversation
    |> where(session_id: ^session_id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end

  def get_conversation!(id) when is_integer(id),
    do: Repo.get!(Conversation, id)

  def create_conversation(session_id, attrs) when is_binary(session_id) and is_map(attrs) do
    %Conversation{session_id: session_id}
    |> Conversation.changeset(Map.merge(%{title: "New conversation"}, attrs))
    |> insert_with_busy_retry(@conversation_insert_retry_attempts)
  end

  def create_conversation(attrs) when is_map(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def create_conversation!(attrs) when is_map(attrs) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert!()
  end

  def rename_conversation(id, title) when is_integer(id) and is_binary(title) do
    normalized_title =
      title
      |> String.trim()
      |> String.slice(0, 80)

    Repo.get!(Conversation, id)
    |> Conversation.changeset(%{title: normalized_title})
    |> Repo.update!()
  end

  def update_conversation_settings(id, attrs) when is_integer(id) and is_map(attrs) do
    normalized =
      attrs
      |> normalize_blank(:model)
      |> normalize_blank(:system_prompt)
      |> normalize_blank(:temperature)

    Repo.get!(Conversation, id)
    |> Conversation.changeset(normalized)
    |> Repo.update()
  end

  def settings_model_or_default(%Conversation{model: model})
      when is_binary(model) and model != "",
      do: model

  def settings_model_or_default(_conversation), do: "gpt-4o-mini"

  def record_usage(conversation_id, message_id, model, usage)
      when is_integer(conversation_id) and is_integer(message_id) and is_binary(model) and
             is_map(usage) do
    prompt_tokens = parse_int(Map.get(usage, "prompt_tokens"))
    completion_tokens = parse_int(Map.get(usage, "completion_tokens"))
    total_tokens = parse_int(Map.get(usage, "total_tokens"))

    estimated_cost_cents = estimate_cost_cents(model, prompt_tokens, completion_tokens)

    attrs = %{
      conversation_id: conversation_id,
      message_id: message_id,
      model: model,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      estimated_cost_cents: estimated_cost_cents
    }

    changeset = UsageRecord.changeset(%UsageRecord{}, attrs)

    if not changeset.valid? do
      {:error, changeset}
    else
      ensure_usage_foreign_rows(conversation_id, message_id)

      %UsageRecord{}
      |> UsageRecord.changeset(attrs)
      |> Repo.insert()
    end
  end

  def usage_for_conversation(conversation_id) when is_integer(conversation_id) do
    from(u in UsageRecord,
      where: u.conversation_id == ^conversation_id,
      select: %{
        total_tokens: coalesce(sum(u.total_tokens), 0),
        total_cost_cents: coalesce(sum(u.estimated_cost_cents), 0)
      }
    )
    |> Repo.one()
  end

  def auto_title_from_first_message(content) when is_binary(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 60)
    |> case do
      "" -> "New conversation"
      value -> value
    end
  end

  def list_messages(conversation_id) when is_integer(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(asc: :inserted_at, asc: :id)
    |> Repo.all()
  end

  def append_message(conversation_id, role, content)
      when is_integer(conversation_id) and role in [:user, :assistant] and is_binary(content) do
    %Message{}
    |> Message.changeset(%{conversation_id: conversation_id, role: role, content: content})
    |> Repo.insert()
  end

  def update_assistant_message(message_id, content)
      when is_integer(message_id) and is_binary(content) do
    Repo.get!(Message, message_id)
    |> Message.changeset(%{content: content})
    |> Repo.update()
  end

  def delete_conversation(conversation_id) when is_integer(conversation_id) do
    Repo.get!(Conversation, conversation_id)
    |> Repo.delete()
  end

  def delete_message(message_id) when is_integer(message_id) do
    case Repo.get(Message, message_id) do
      nil -> {:error, :not_found}
      message -> Repo.delete(message)
    end
  end

  def reset_conversation(session_id) when is_binary(session_id) do
    Repo.delete_all(from(c in Conversation, where: c.session_id == ^session_id))
  end

  def get_message!(message_id) when is_integer(message_id) do
    Repo.get!(Message, message_id)
  end

  def conversation_count do
    Repo.aggregate(Conversation, :count, :id)
  end

  def message_count_for_conversation(conversation_id) when is_integer(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> Repo.aggregate(:count, :id)
  end

  def latest_message_conversation do
    Message
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      message -> Repo.get(Conversation, message.conversation_id)
    end
  end

  defp estimate_cost_cents(model, prompt_tokens, completion_tokens) do
    case Map.get(@prices_per_1m_tokens, model) do
      nil ->
        Logger.warning("unknown model for usage pricing: #{model}")
        0

      %{prompt: prompt_price, completion: completion_price} ->
        round(prompt_tokens * prompt_price / 1_000_000) +
          round(completion_tokens * completion_price / 1_000_000)
    end
  end

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> 0
    end
  end

  defp parse_int(_), do: 0

  defp ensure_usage_foreign_rows(conversation_id, message_id) do
    case Repo.get(Conversation, conversation_id) do
      nil ->
        Repo.insert(
          %Conversation{
            id: conversation_id,
            session_id: "usage-#{conversation_id}",
            title: "Usage"
          },
          on_conflict: :nothing,
          conflict_target: :id
        )

      _ ->
        :ok
    end

    case Repo.get(Message, message_id) do
      nil ->
        Repo.insert(
          %Message{
            id: message_id,
            conversation_id: conversation_id,
            role: :assistant,
            content: ""
          },
          on_conflict: :nothing,
          conflict_target: :id
        )

      _ ->
        :ok
    end
  end

  defp normalize_blank(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          Map.put(attrs, key, nil)
        else
          attrs
        end

      _ ->
        attrs
    end
  end

  defp insert_with_busy_retry(changeset, attempts_left) do
    Repo.insert!(changeset)
  rescue
    e in Exqlite.Error ->
      maybe_retry_busy_insert(e, changeset, attempts_left, __STACKTRACE__)

    e in DBConnection.ConnectionError ->
      maybe_retry_busy_insert(e, changeset, attempts_left, __STACKTRACE__)
  end

  defp maybe_retry_busy_insert(error, changeset, attempts_left, stacktrace) do
    if sqlite_busy_or_locked?(error) and attempts_left > 1 do
      delay =
        (@conversation_insert_retry_attempts - attempts_left + 1) *
          @conversation_insert_retry_backoff_ms

      Process.sleep(delay)
      insert_with_busy_retry(changeset, attempts_left - 1)
    else
      reraise error, stacktrace
    end
  end

  defp sqlite_busy_or_locked?(error) do
    message = error |> Exception.message() |> String.downcase()
    String.contains?(message, "database busy") or String.contains?(message, "database is locked")
  end
end
