defmodule ChatApp.Conversations.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(user assistant)a

  schema "messages" do
    field(:role, Ecto.Enum, values: @roles)
    field(:content, :string)

    belongs_to(:conversation, ChatApp.Conversations.Conversation)

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content], empty_values: [])
    |> validate_required([:conversation_id, :role])
    |> require_content_value()
    |> validate_inclusion(:role, @roles)
  end

  defp require_content_value(changeset) do
    if is_nil(get_field(changeset, :content)) do
      add_error(changeset, :content, "can't be blank")
    else
      changeset
    end
  end
end
