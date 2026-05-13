defmodule ChatApp.Clothing.PriceHistory do
  use Ecto.Schema

  schema "price_history" do
    field(:price, ChatApp.Ecto.DecimalString)
    field(:currency, :string)
    belongs_to(:item, ChatApp.Clothing.Item)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
