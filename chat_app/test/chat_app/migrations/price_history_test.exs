defmodule ChatApp.Migrations.PriceHistoryTest do
  use ChatApp.DataCase, async: false

  # -- helpers -----------------------------------------------------------------

  defp table_columns(table) do
    {:ok, result} = Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA table_info(#{table})", [])
    Enum.map(result.rows, fn row -> %{name: Enum.at(row, 1), type: Enum.at(row, 2)} end)
  end

  defp column_names(table), do: Enum.map(table_columns(table), & &1.name)

  # Inserts a clothing_item row with all new SP-00-02 columns. Requires the
  # enhance_clothing_items migration to be present — will fail in red phase.
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

  defp insert_price_history(item_id) do
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO price_history (item_id, inserted_at) VALUES (?, ?)",
      [item_id, "2026-05-06 00:00:00"]
    )
  end

  # SQLite does not enforce FK constraints by default. Enable them for every
  # test in this file — without this pragma, FK tests give false greens.
  setup do
    Ecto.Adapters.SQL.query!(ChatApp.Repo, "PRAGMA foreign_keys = ON", [])
    :ok
  end

  # -- U7 ----------------------------------------------------------------------

  # U7
  test "price_history table exists with expected columns" do
    names = column_names("price_history")
    assert names != [], "price_history table does not exist"
    assert "item_id" in names
    assert "inserted_at" in names
  end

  # -- U8 ----------------------------------------------------------------------

  # U8
  test "price_history FK enforced on insert with pragma on" do
    assert {:error, %{message: msg}} = insert_price_history(99_999)
    assert msg =~ "FOREIGN KEY constraint failed"
  end

  # -- U9 ----------------------------------------------------------------------

  # U9
  test "deleting a clothing_item cascades to price_history" do
    item_id = insert_clothing_item()
    assert {:ok, _} = insert_price_history(item_id)

    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "DELETE FROM clothing_items WHERE id = ?",
        [item_id]
      )

    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT count(*) FROM price_history WHERE item_id = ?",
        [item_id]
      )

    assert [[0]] == result.rows
  end
end
