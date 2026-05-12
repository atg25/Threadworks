defmodule ChatApp.Migrations.ClothingVecTest do
  use ChatApp.DataCase, async: false

  alias ChatApp.AI.VectorCodec

  # -- U17 -- clothing_vec virtual table exists
  test "U17: clothing_vec virtual table exists" do
    {:ok, result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT name FROM sqlite_master WHERE type='table' AND name='clothing_vec'",
        []
      )

    assert length(result.rows) == 1
  end

  # -- U18 -- clothing_vec accepts a 512-dim float32 embedding insert
  test "U18: clothing_vec accepts a 512-dim float32 embedding insert" do
    embedding_binary = VectorCodec.encode(List.duplicate(0.1, 512))

    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)",
      [1, {:blob, embedding_binary}]
    )

    {:ok, result} =
      Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT count(*) FROM clothing_vec", [])

    count = hd(hd(result.rows))
    assert count == 1
  end

  # -- U19 -- clothing_vec rowid matches the intended clothing_item id
  test "U19: clothing_vec rowid matches the intended clothing_item id" do
    ts = "2026-05-06 00:00:00"

    # Insert a clothing_item and capture its id
    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      """
      INSERT INTO clothing_items (title, brand, price, url, source, source_id, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """,
      ["Test Item", "TestBrand", "50.00", "http://example.com/test", "test", "999", ts, ts]
    )

    {:ok, item_result} =
      Ecto.Adapters.SQL.query(
        ChatApp.Repo,
        "SELECT id FROM clothing_items WHERE title = 'Test Item'",
        []
      )

    item_id = hd(item_result.rows) |> hd()

    # Insert into clothing_vec with the same rowid
    embedding_binary = VectorCodec.encode(List.duplicate(0.1, 512))

    Ecto.Adapters.SQL.query(
      ChatApp.Repo,
      "INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)",
      [item_id, {:blob, embedding_binary}]
    )

    # Query and verify rowid matches
    {:ok, vec_result} =
      Ecto.Adapters.SQL.query(ChatApp.Repo, "SELECT rowid FROM clothing_vec", [])

    returned_rowid = hd(vec_result.rows) |> hd()
    assert returned_rowid == item_id
  end
end
