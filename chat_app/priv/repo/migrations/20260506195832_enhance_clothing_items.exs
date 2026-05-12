defmodule ChatApp.Repo.Migrations.EnhanceClothingItems do
  use Ecto.Migration

  def change do
    alter table(:clothing_items) do
      add :source, :string, null: false
      add :source_id, :string
      add :style_tags, :string
      add :color, :string
      add :size_normalized, :string
      add :condition_normalized, :string
      add :last_scraped_at, :utc_datetime
    end

    create unique_index(:clothing_items, [:source, :source_id])
  end
end
