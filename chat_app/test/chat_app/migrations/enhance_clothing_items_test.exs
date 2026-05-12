defmodule ChatApp.Migrations.EnhanceClothingItemsTest do
  use ChatApp.DataCase, async: false

  # -- helpers -----------------------------------------------------------------

  defp table_columns(table) do
    {:ok, result} = Ecto.Adapters.SQL.query(ChatApp.Repo, "PRAGMA table_info(#{table})", [])
    Enum.map(result.rows, fn row -> %{name: Enum.at(row, 1), type: Enum.at(row, 2)} end)
  end

  defp column_names(table) do
    Enum.map(table_columns(table), & &1.name)
  end

  defp insert_clothing_item(source, source_id) do
    ts = "2026-05-06 00:00:00"
    url = "http://example.com/#{System.unique_integer([:positive])}"

    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      """
      INSERT INTO clothing_items
        (title, brand, price, url, source, source_id, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      ["Test Item", "TestBrand", "10.00", url, source, source_id, ts, ts]
    )
  end

  # -- U1 ----------------------------------------------------------------------

  # U1
  test "clothing_items has source column of type TEXT" do
    columns = table_columns("clothing_items")
    assert Enum.any?(columns, &(&1.name == "source" and &1.type == "TEXT"))
  end

  # -- U2 ----------------------------------------------------------------------

  # U2
  test "clothing_items has source_id column" do
    assert "source_id" in column_names("clothing_items")
  end

  # -- U3 ----------------------------------------------------------------------

  # U3
  test "clothing_items has embedding column of type BLOB" do
    columns = table_columns("clothing_items")
    assert Enum.any?(columns, &(&1.name == "embedding" and &1.type == "BLOB"))
  end

  # -- U4 ----------------------------------------------------------------------

  # U4
  test "clothing_items has style_tags column" do
    assert "style_tags" in column_names("clothing_items")
  end

  # -- U5 ----------------------------------------------------------------------

  # U5
  test "clothing_items has last_scraped_at column" do
    assert "last_scraped_at" in column_names("clothing_items")
  end

  # -- U5a ---------------------------------------------------------------------

  # U5a
  test "clothing_items has color column" do
    assert "color" in column_names("clothing_items")
  end

  # -- U5b ---------------------------------------------------------------------

  # U5b
  test "clothing_items has size_normalized column" do
    assert "size_normalized" in column_names("clothing_items")
  end

  # -- U5c ---------------------------------------------------------------------

  # U5c
  test "clothing_items has condition_normalized column" do
    assert "condition_normalized" in column_names("clothing_items")
  end

  # -- U6a ---------------------------------------------------------------------

  # U6a
  test "unique index rejects duplicate source and source_id pair" do
    assert {:ok, _} = insert_clothing_item("ebay", "abc123")
    assert {:error, %{message: msg}} = insert_clothing_item("ebay", "abc123")
    assert msg =~ "UNIQUE constraint failed"
  end

  # -- U6b ---------------------------------------------------------------------

  # U6b
  test "unique index allows rows with distinct source_id values" do
    assert {:ok, _} = insert_clothing_item("ebay", "1")
    assert {:ok, _} = insert_clothing_item("ebay", "2")
  end

  # -- U6c ---------------------------------------------------------------------

  # U6c
  test "unique index allows multiple rows with NULL source_id" do
    assert {:ok, _} = insert_clothing_item("ebay", nil)
    assert {:ok, _} = insert_clothing_item("ebay", nil)
  end
end
