defmodule ChatApp.Conversations.UsageRecord do
  use Ecto.Schema
  import Ecto.Changeset

  schema "usage_records" do
    field(:model, :string)
    field(:prompt_tokens, :integer)
    field(:completion_tokens, :integer)
    field(:total_tokens, :integer)
    field(:estimated_cost_cents, :integer)

    belongs_to(:conversation, ChatApp.Conversations.Conversation)
    belongs_to(:message, ChatApp.Conversations.Message)

    timestamps(type: :utc_datetime)
  end

  def changeset(usage_record, attrs) do
    usage_record
    |> cast(attrs, [
      :conversation_id,
      :message_id,
      :model,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :estimated_cost_cents
    ])
    |> validate_required([
      :conversation_id,
      :message_id,
      :model,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens,
      :estimated_cost_cents
    ])
    |> validate_number(:prompt_tokens, greater_than: 0)
    |> validate_number(:completion_tokens, greater_than: 0)
    |> validate_number(:total_tokens, greater_than: 0)
    |> validate_number(:estimated_cost_cents, greater_than_or_equal_to: 0)
  end
end
