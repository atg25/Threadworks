defmodule ChatApp.Repo.Migrations.AllowMultipleConversationsPerSession do
  use Ecto.Migration

  def change do
    drop unique_index(:conversations, [:session_id])
    create index(:conversations, [:session_id])
  end
end
