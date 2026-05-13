defmodule ChatApp.Repo.Migrations.SavedItemsPriceAsText do
  use Ecto.Migration

  # SQLite's DECIMAL affinity coerces stored strings to numbers, stripping
  # trailing zeros (e.g. "19.90" -> 19.9). Recreating the table with TEXT
  # affinity for price_at_save preserves the exact decimal string.
  #
  # SQLite does not support ALTER COLUMN.
  def up do
    drop index(:saved_items, [:user_id])
    drop unique_index(:saved_items, [:user_id, :item_id])
    execute "ALTER TABLE saved_items RENAME TO saved_items_old"

    create table(:saved_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:clothing_items, on_delete: :nilify_all)
      add :price_at_save, :string
      add :notes, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:saved_items, [:user_id])
    create unique_index(:saved_items, [:user_id, :item_id])

    execute """
    INSERT INTO saved_items (id, user_id, item_id, price_at_save, notes, inserted_at)
    SELECT id, user_id, item_id, CAST(price_at_save AS TEXT), notes, inserted_at
    FROM saved_items_old
    """

    execute "DROP TABLE saved_items_old"
  end

  def down do
    drop index(:saved_items, [:user_id])
    drop unique_index(:saved_items, [:user_id, :item_id])
    execute "ALTER TABLE saved_items RENAME TO saved_items_old"

    create table(:saved_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:clothing_items, on_delete: :nilify_all)
      add :price_at_save, :decimal
      add :notes, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:saved_items, [:user_id])
    create unique_index(:saved_items, [:user_id, :item_id])

    execute """
    INSERT INTO saved_items (id, user_id, item_id, price_at_save, notes, inserted_at)
    SELECT id, user_id, item_id, price_at_save, notes, inserted_at
    FROM saved_items_old
    """

    execute "DROP TABLE saved_items_old"
  end
end

