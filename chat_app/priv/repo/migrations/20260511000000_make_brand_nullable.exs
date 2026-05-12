defmodule ChatApp.Repo.Migrations.MakeBrandNullable do
  use Ecto.Migration

  # SQLite does not support ALTER COLUMN, so we recreate the table without
  # the NOT NULL constraint on brand. eBay items do not carry a brand field.
  def up do
    execute """
    CREATE TABLE clothing_items_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      brand TEXT,
      size TEXT,
      condition TEXT,
      price DECIMAL NOT NULL,
      url TEXT NOT NULL,
      image_url TEXT,
      description TEXT,
      embedding BLOB,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      source TEXT NOT NULL,
      source_id TEXT,
      style_tags TEXT,
      color TEXT,
      size_normalized TEXT,
      condition_normalized TEXT,
      last_scraped_at TEXT
    )
    """

    execute "INSERT INTO clothing_items_new SELECT * FROM clothing_items"
    execute "DROP TABLE clothing_items"
    execute "ALTER TABLE clothing_items_new RENAME TO clothing_items"
    execute "CREATE UNIQUE INDEX IF NOT EXISTS clothing_items_source_source_id_index ON clothing_items (source, source_id)"
    execute "CREATE INDEX IF NOT EXISTS clothing_items_brand_index ON clothing_items (brand)"
  end

  def down do
    execute """
    CREATE TABLE clothing_items_old (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      brand TEXT NOT NULL,
      size TEXT,
      condition TEXT,
      price DECIMAL NOT NULL,
      url TEXT NOT NULL,
      image_url TEXT,
      description TEXT,
      embedding BLOB,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      source TEXT NOT NULL,
      source_id TEXT,
      style_tags TEXT,
      color TEXT,
      size_normalized TEXT,
      condition_normalized TEXT,
      last_scraped_at TEXT
    )
    """

    execute "INSERT INTO clothing_items_old SELECT * FROM clothing_items"
    execute "DROP TABLE clothing_items"
    execute "ALTER TABLE clothing_items_old RENAME TO clothing_items"
    execute "CREATE UNIQUE INDEX IF NOT EXISTS clothing_items_source_source_id_index ON clothing_items (source, source_id)"
    execute "CREATE INDEX IF NOT EXISTS clothing_items_brand_index ON clothing_items (brand)"
  end
end
