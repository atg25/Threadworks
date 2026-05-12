defmodule ChatApp.Repo.Migrations.CreateClothingFts do
  use Ecto.Migration

  def up do
    execute("""
    CREATE VIRTUAL TABLE IF NOT EXISTS clothing_fts
    USING fts5(
      title,
      content='clothing_items',
      content_rowid='id'
    )
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS clothing_fts")
  end
end
