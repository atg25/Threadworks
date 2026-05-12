defmodule ChatApp.Migrations.SavedItemsTest do
  use ChatApp.DataCase, async: false

  # -- helpers -----------------------------------------------------------------

  defp table_columns(table) do
    {:ok, result} = Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA table_info(#{table})", [])
    Enum.map(result.rows, fn row -> %{name: Enum.at(row, 1), type: Enum.at(row, 2)} end)
  end

  defp column_names(table), do: Enum.map(table_columns(table), & &1.name)

  defp insert_user do
    email = "test#{System.unique_integer([:positive])}@example.com"
    ts = "2026-05-06 00:00:00"

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "INSERT INTO users (email, inserted_at, updated_at) VALUES (?, ?, ?)",
        [email, ts, ts]
      )

    {:ok, row} = Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT last_insert_rowid()", [])
    row.rows |> hd() |> hd()
  end

  # Requires the enhance_clothing_items migration — will fail in red phase.
  defp insert_clothing_item do
    ts = "2026-05-06 00:00:00"
    url = "http://example.com/#{System.unique_integer([:positive])}"

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        """
        INSERT INTO clothing_items
          (title, brand, price, url, source, source_id, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ["Test Item", "TestBrand", "10.00", url, "ebay", "item-#{System.unique_integer()}", ts, ts]
      )

    {:ok, row} = Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT last_insert_rowid()", [])
    row.rows |> hd() |> hd()
  end

  defp insert_saved_item(user_id, item_id) do
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO saved_items (user_id, item_id, inserted_at) VALUES (?, ?, ?)",
      [user_id, item_id, "2026-05-06 00:00:00"]
    )
  end

  # SQLite does not enforce FK constraints by default.
  setup do
    Ecto.Adapters.SQL.query!(ChatApp.Repo, "PRAGMA foreign_keys = ON", [])
    :ok
  end

  # -- U10 ---------------------------------------------------------------------

  # U10
  test "saved_items table exists with all expected columns" do
    names = column_names("saved_items")
    assert names != [], "saved_items table does not exist"
    assert "user_id" in names
    assert "item_id" in names
    assert "price_at_save" in names
    assert "notes" in names
    assert "inserted_at" in names
  end

  # -- U11 ---------------------------------------------------------------------

  # U11
  test "unique index prevents duplicate user and item pair" do
    user_id = insert_user()
    item_id = insert_clothing_item()

    assert {:ok, _} = insert_saved_item(user_id, item_id)
    assert {:error, %{message: msg}} = insert_saved_item(user_id, item_id)
    assert msg =~ "UNIQUE constraint failed"
  end

  # -- U12 ---------------------------------------------------------------------

  # U12
  test "deleting a clothing_item sets saved_items.item_id to NULL" do
    user_id = insert_user()
    item_id = insert_clothing_item()

    {:ok, _} = insert_saved_item(user_id, item_id)

    {:ok, saved_row} =
      Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT last_insert_rowid()", [])

    saved_id = saved_row.rows |> hd() |> hd()

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "DELETE FROM clothing_items WHERE id = ?",
        [item_id]
      )

    # Row still exists
    {:ok, count_result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT count(*) FROM saved_items WHERE id = ?",
        [saved_id]
      )

    assert [[1]] == count_result.rows

    # item_id is now NULL
    {:ok, null_result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT item_id FROM saved_items WHERE id = ?",
        [saved_id]
      )

    assert [[nil]] == null_result.rows
  end

  # -- U13 ---------------------------------------------------------------------

  # U13
  test "saved_items.item_id accepts NULL on direct insert" do
    user_id = insert_user()
    assert {:ok, _} = insert_saved_item(user_id, nil)
  end

  # -- U14 ---------------------------------------------------------------------

  # U14
  test "saved_items user_id FK enforced with pragma on" do
    assert {:error, %{message: msg}} = insert_saved_item(99_999, nil)
    assert msg =~ "FOREIGN KEY constraint failed"
  end
end
