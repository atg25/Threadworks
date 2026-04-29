defmodule ChatApp.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :session_id, :string, null: false
      add :title, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:conversations, [:session_id])

    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
  end
end
