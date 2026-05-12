defmodule ChatApp.Repo.Migrations.CreatePriceHistory do
  use Ecto.Migration

  def change do
    create table(:price_history) do
      add :item_id, references(:clothing_items, on_delete: :delete_all), null: false
      add :price, :decimal
      add :currency, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:price_history, [:item_id])
  end
end
