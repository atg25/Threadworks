defmodule ChatApp.Repo.Migrations.CreateUsageRecords do
  use Ecto.Migration

  def change do
    create table(:usage_records) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :model, :string, null: false
      add :prompt_tokens, :integer, null: false
      add :completion_tokens, :integer, null: false
      add :total_tokens, :integer, null: false
      add :estimated_cost_cents, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:usage_records, [:conversation_id])
    create index(:usage_records, [:message_id])
  end
end
