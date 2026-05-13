defmodule ChatApp.Search.VectorStore do
  @moduledoc """
  KNN vector search backed by the `clothing_vec` sqlite-vec virtual table.

  sqlite_vec Hex 0.1.0 / native 0.1.5; smoke-tested 2026-05-11.
  MATCH syntax: `WHERE embedding MATCH ?` with a VectorCodec-encoded blob.
  """

  alias ChatApp.AI.VectorCodec
  alias ChatApp.Repo

  @doc """
  Inserts or replaces a 512-dim float vector for the given item_id.

  Encodes the vector via VectorCodec (propagates ArgumentError / FunctionClauseError
  on bad input). Returns `:ok` on success.
  """
  def upsert(item_id, vector) do
    blob = VectorCodec.encode(vector)
    # vec0 virtual tables do not honour the OR REPLACE conflict clause, so we
    # delete the existing row first to achieve idempotent upsert semantics.
    # Wrapped in a transaction so a failed INSERT after a successful DELETE does
    # not permanently orphan the item from the index.
    Repo.transaction(fn ->
      Repo.query!("DELETE FROM clothing_vec WHERE rowid = ?", [item_id])
      Repo.query!("INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)", [item_id, {:blob, blob}])
    end)
    :ok
  end

  @doc """
  Returns the `top_n` nearest items to `query_vector` as `[{item_id, distance}]`,
  sorted closest-first. Returns `[]` when the table is empty.
  """
  def search(query_vector, top_n) do
    blob = VectorCodec.encode(query_vector)

    result =
      Repo.query!(
        "SELECT rowid, distance FROM clothing_vec WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
        [{:blob, blob}, top_n]
      )

    Enum.map(result.rows, fn [rowid, distance] ->
      {rowid, distance * 1.0}
    end)
  end
end
