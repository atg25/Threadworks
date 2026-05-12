defmodule ChatApp.Repo.Migrations.AddClothingFtsMeta do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE IF NOT EXISTS clothing_fts_meta (
      item_id INTEGER PRIMARY KEY,
      indexed_title TEXT NOT NULL
    )
    """)
  end

  def down do
    execute("DROP TABLE IF EXISTS clothing_fts_meta")
  end
end
