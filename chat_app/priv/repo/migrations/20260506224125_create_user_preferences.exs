defmodule ChatApp.Repo.Migrations.CreateUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:user_preferences, [:user_id])
  end
end
