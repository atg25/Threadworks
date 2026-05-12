defmodule ChatApp.Repo.Migrations.CreateClothingItems do
  use Ecto.Migration

  def change do
    create table(:clothing_items) do
      add :title, :string, null: false
      add :brand, :string, null: false
      add :size, :string
      add :condition, :string
      add :price, :decimal, null: false
      add :url, :string, null: false
      add :image_url, :string
      add :description, :text
      add :embedding, :binary

      timestamps(type: :utc_datetime)
    end
    
    create index(:clothing_items, [:brand])
  end
end
