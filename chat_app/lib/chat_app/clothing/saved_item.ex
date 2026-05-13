defmodule ChatApp.Clothing.SavedItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_items" do
    field(:price_at_save, ChatApp.Ecto.DecimalString)
    field(:notes, :string)
    belongs_to(:user, ChatApp.Accounts.User)
    belongs_to(:item, ChatApp.Clothing.Item)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(saved_item, attrs) do
    saved_item
    |> cast(attrs, [:user_id, :item_id, :price_at_save, :notes])
    |> validate_required([:user_id])
  end
end
