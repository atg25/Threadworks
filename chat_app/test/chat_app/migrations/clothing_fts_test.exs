defmodule ChatApp.Migrations.ClothingFtsTest do
  use ChatApp.DataCase, async: false

  # -- U13 -- clothing_fts virtual table exists
  test "U13: clothing_fts virtual table exists" do
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='clothing_fts'",
        []
      )

    assert length(result.rows) == 1
  end

  # -- U14 -- FTS5 does NOT index a row that was inserted before a rebuild
  test "U14: FTS5 does NOT index a row that was inserted before a rebuild" do
    ts = "2026-05-06 00:00:00"

    # Insert a clothing_item with title "Zara Coat"
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      """
      INSERT INTO clothing_items (title, brand, price, url, source, source_id, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      ["Zara Coat", "Zara", "100.00", "http://example.com/zara", "zara", "12345", ts, ts]
    )

    # Do NOT run a rebuild, search for 'zara'
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'zara'",
        []
      )

    # Should have empty result set - no rebuild means no indexing
    assert length(result.rows) == 0
  end

  # -- U15 -- FTS5 indexes a row after explicit rebuild
  test "U15: FTS5 indexes a row after explicit rebuild" do
    ts = "2026-05-06 00:00:00"

    # Insert a clothing_item with title "Levi Jacket"
    {:ok, _} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        """
        INSERT INTO clothing_items (title, brand, price, url, source, source_id, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        ["Levi Jacket", "Levi's", "80.00", "http://example.com/levi", "levis", "67890", ts, ts]
      )

    # Get the inserted item's id
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT id FROM clothing_items WHERE title = 'Levi Jacket'",
        []
      )

    item_id = hd(result.rows) |> hd()

    # Run rebuild
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO clothing_fts(clothing_fts) VALUES('rebuild')",
      []
    )

    # Now search for 'levi'
    {:ok, search_result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'levi'",
        []
      )

    # Should have non-empty result with matching rowid
    assert length(search_result.rows) > 0
    returned_rowid = hd(search_result.rows) |> hd()
    assert returned_rowid == item_id
  end

  # -- U16 -- FTS5 returns no result for a term not present in any title
  test "U16: FTS5 returns no result for a term not present in any title" do
    ts = "2026-05-06 00:00:00"

    # Insert a clothing_item with title "Levi Jacket"
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      """
      INSERT INTO clothing_items (title, brand, price, url, source, source_id, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      ["Levi Jacket", "Levi's", "80.00", "http://example.com/levi", "levis", "67890", ts, ts]
    )

    # Run rebuild
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO clothing_fts(clothing_fts) VALUES('rebuild')",
      []
    )

    # Search for 'adidas' which should not be in any title
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT rowid FROM clothing_fts WHERE clothing_fts MATCH 'adidas'",
        []
      )

    # Should have empty result set
    assert length(result.rows) == 0
  end
end
