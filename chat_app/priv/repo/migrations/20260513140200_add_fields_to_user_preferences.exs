defmodule ChatApp.Repo.Migrations.AddFieldsToUserPreferences do
  use Ecto.Migration

  def change do
    alter table(:user_preferences) do
      add :sizes, :text, null: false, default: "[]"
      add :brands, :text, null: false, default: "[]"
      add :budget_min, :decimal
      add :budget_max, :decimal
      add :style_keywords, :text, null: false, default: "[]"
    end
  end
end
