defmodule ChatApp.Conversations.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @models ["gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini"]

  schema "conversations" do
    field(:session_id, :string)
    field(:title, :string)
    field(:model, :string)
    field(:system_prompt, :string)
    field(:temperature, :float)

    has_many(:messages, ChatApp.Conversations.Message)
    has_many(:usage_records, ChatApp.Conversations.UsageRecord)

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:session_id, :title, :model, :system_prompt, :temperature])
    |> validate_required([:session_id])
    |> validate_length(:title, max: 80)
    |> validate_inclusion(:model, @models, allow_nil: true)
    |> validate_length(:system_prompt, max: 4000)
    |> validate_number(:temperature, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 2.0)
    |> unique_constraint(:session_id)
  end
end
