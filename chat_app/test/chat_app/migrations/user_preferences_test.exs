defmodule ChatApp.Migrations.UserPreferencesTest do
  use ChatApp.DataCase, async: false

  # -- U10 -- user_preferences table exists
  test "U10: user_preferences table exists" do
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='user_preferences'",
        []
      )

    assert length(result.rows) == 1
  end

  # -- U11 -- user_preferences unique index prevents duplicate user_id
  test "U11: user_preferences unique index prevents duplicate user_id" do
    ts = "2026-05-06 00:00:00"

    # Insert a minimal user so the FK constraint is satisfied
    Ecto.Adapters.SQL.query!(
      ChatApp.Repo,
      "INSERT INTO users (email, hashed_password, inserted_at, updated_at) VALUES (?, ?, ?, ?)",
      ["u11@example.com", "x", ts, ts]
    )

    {:ok, %{rows: [[user_id]]}} =
      Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT last_insert_rowid()", [])

    # Insert first preference row — must succeed
    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "INSERT INTO user_preferences (user_id, inserted_at, updated_at) VALUES (?, ?, ?)",
        [user_id, ts, ts]
      )

    # Second insert with same user_id must raise on the UNIQUE constraint
    assert_raise Exqlite.Error, fn ->
      Ecto.Adapters.SQL.query!(
        ChatApp.Repo,
        "INSERT INTO user_preferences (user_id, inserted_at, updated_at) VALUES (?, ?, ?)",
        [user_id, ts, ts]
      )
    end
  end

  # -- U12 -- user_preferences user_id FK references users
  test "U12: user_preferences user_id FK references users" do
    # Enable foreign keys
    Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA foreign_keys = ON", [])

    {:ok, result} =
      Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA foreign_key_list(user_preferences)", [])

    # Result should have rows with table = "users" and to = "id"
    fk_exists =
      Enum.any?(result.rows, fn row ->
        table = Enum.at(row, 2)
        to_col = Enum.at(row, 4)
        table == "users" and to_col == "id"
      end)

    assert fk_exists, "Foreign key from user_preferences.user_id to users.id not found"
  end
end
