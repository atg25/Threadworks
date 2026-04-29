defmodule ChatApp.Repo.Migrations.AddSettingsToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :model, :string
      add :system_prompt, :text
      add :temperature, :float
    end
  end
end
