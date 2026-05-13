defmodule ChatApp.Migrations.MigrationIntegrationTest do
  use ChatApp.DataCase, async: false

  defp table_exists?(table) do
    {:ok, result} = Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA table_info(#{table})", [])
    result.rows != []
  end

  defp column_names(table) do
    {:ok, result} = Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA table_info(#{table})", [])
    Enum.map(result.rows, fn row -> Enum.at(row, 1) end)
  end

  # -- I1 ----------------------------------------------------------------------

  # I1
  test "all four SP-00-02 migration artifacts are present in the database" do
    # Migration 1 — Oban jobs table
    assert table_exists?("oban_jobs"),
           "oban_jobs table is missing — Oban migration did not run"

    # Migration 2 — enhance_clothing_items (source column is the sentinel)
    names = column_names("clothing_items")

    assert "source" in names,
           "clothing_items.source column missing — enhance_clothing_items migration did not run"

    # Migration 3 — price_history
    assert table_exists?("price_history"),
           "price_history table is missing — create_price_history migration did not run"

    # Migration 4 — saved_items
    assert table_exists?("saved_items"),
           "saved_items table is missing — create_saved_items migration did not run"
  end

  # -- I2 ----------------------------------------------------------------------

  # I2
  test "Ecto.Migrator.run is idempotent — no new migrations applied on second invocation" do
    priv_path = Path.join(:code.priv_dir(:chat_app), "repo/migrations")
    newly_migrated = Ecto.Migrator.run(ChatApp.Repo, priv_path, :up, all: true)

    assert newly_migrated == [],
           "Expected no new migrations on second run, but these were applied: #{inspect(newly_migrated)}"
  end

  # -- SP-00-03 I1 -------------------------------------------------------------

  # SP-00-03 I1
  # Verifies that all three SP-00-03 migration artifacts are present after
  # mix ecto.migrate runs migrations 5–7 on top of an already-migrated 1–4 DB.
  test "SP-00-03: migrations 5-7 artifacts are present (user_preferences, clothing_fts, clothing_vec)" do
    assert table_exists?("user_preferences"),
           "user_preferences table is missing — migration 5 (create_user_preferences) did not run"

    assert table_exists?("clothing_fts"),
           "clothing_fts virtual table is missing — migration 6 (create_clothing_fts) did not run"

    assert table_exists?("clothing_vec"),
           "clothing_vec virtual table is missing — migration 7 (create_clothing_vec) did not run"
  end

  # SP-00-03 I2
  # Verifies idempotence of the full 7-migration set: a second Ecto.Migrator.run
  # must apply zero new migrations (i.e. all CREATE VIRTUAL TABLE calls use
  # IF NOT EXISTS and do not crash on re-run).
  test "SP-00-03: Ecto.Migrator.run is idempotent over all 7 migrations" do
    priv_path = Path.join(:code.priv_dir(:chat_app), "repo/migrations")
    newly_migrated = Ecto.Migrator.run(ChatApp.Repo, priv_path, :up, all: true)

    assert newly_migrated == [],
           "Expected no new migrations on second run over all 7, but these were applied: #{inspect(newly_migrated)}"
  end
end
