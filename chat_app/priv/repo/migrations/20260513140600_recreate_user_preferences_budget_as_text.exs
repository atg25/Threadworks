defmodule ChatApp.Repo.Migrations.RecreateUserPreferencesBudgetAsText do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE user_preferences_new (
      id INTEGER PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      sizes TEXT NOT NULL DEFAULT '[]',
      brands TEXT NOT NULL DEFAULT '[]',
      budget_min TEXT,
      budget_max TEXT,
      style_keywords TEXT NOT NULL DEFAULT '[]',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO user_preferences_new (
      id, user_id, sizes, brands, budget_min, budget_max, style_keywords, inserted_at, updated_at
    )
    SELECT
      id,
      user_id,
      sizes,
      brands,
      budget_min,
      budget_max,
      style_keywords,
      inserted_at,
      updated_at
    FROM user_preferences
    """)

    drop table(:user_preferences)
    rename table(:user_preferences_new), to: table(:user_preferences)
    create unique_index(:user_preferences, [:user_id])
  end

  def down do
    raise "Irreversible migration"
  end
end
