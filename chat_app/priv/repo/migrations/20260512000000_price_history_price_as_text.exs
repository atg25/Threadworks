defmodule ChatApp.Repo.Migrations.PriceHistoryPriceAsText do
  use Ecto.Migration

  # SQLite's DECIMAL affinity coerces stored strings to numbers, stripping
  # trailing zeros (e.g. "10.00" → 10). Recreating the table with TEXT affinity
  # for the price column preserves the exact decimal string so Decimal.new("10.00")
  # round-trips correctly. SQLite does not support ALTER COLUMN.
  def up do
    drop index(:price_history, [:item_id])
    execute "ALTER TABLE price_history RENAME TO price_history_old"

    create table(:price_history) do
      add :item_id, references(:clothing_items, on_delete: :delete_all), null: false
      add :price, :string
      add :currency, :string
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:price_history, [:item_id])

    execute "INSERT INTO price_history SELECT id, item_id, CAST(price AS TEXT), currency, inserted_at FROM price_history_old"
    execute "DROP TABLE price_history_old"
  end

  def down do
    drop index(:price_history, [:item_id])
    execute "ALTER TABLE price_history RENAME TO price_history_old"

    create table(:price_history) do
      add :item_id, references(:clothing_items, on_delete: :delete_all), null: false
      add :price, :decimal
      add :currency, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:price_history, [:item_id])

    execute "INSERT INTO price_history SELECT id, item_id, price, currency, inserted_at FROM price_history_old"
    execute "DROP TABLE price_history_old"
  end
end
