defmodule ChatApp.ETL.FTS5Index do
  alias ChatApp.Repo

  def upsert(item_id) do
    # clothing_fts is an FTS5 content table (content='clothing_items'). A plain
    # INSERT populates the FTS shadow index for the given row. We use the
    # non-bang variant so a duplicate-rowid insert (e.g. on Oban retry after a
    # partial run) fails silently — the existing index entry is already correct.
    %{rows: rows} =
      Repo.query!("SELECT title FROM clothing_items WHERE id = ?", [item_id])

    case rows do
      [[title]] ->
        Repo.query(
          "INSERT INTO clothing_fts(rowid, title) VALUES (?, ?)",
          [item_id, title]
        )

      _ ->
        :ok
    end

    :ok
  end
end
