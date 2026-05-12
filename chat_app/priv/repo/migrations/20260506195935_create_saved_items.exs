defmodule ChatApp.Repo.Migrations.CreateSavedItems do
  use Ecto.Migration

  def change do
    create table(:saved_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:clothing_items, on_delete: :nilify_all)
      add :price_at_save, :decimal
      add :notes, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:saved_items, [:user_id])
    create unique_index(:saved_items, [:user_id, :item_id])
  end
end
