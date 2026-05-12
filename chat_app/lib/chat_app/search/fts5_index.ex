defmodule ChatApp.Search.FTS5Index do
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo
  alias ChatApp.Search.QueryProcessor

  @doc """
  Delegates to `QueryProcessor.escape_fts_query/1`.
  """
  def escape_fts_query(query_text), do: QueryProcessor.escape_fts_query(query_text)

  @doc """
  Upserts the FTS5 index entry for the given `item_id`.

  Uses the external content table delete-then-insert pattern required by FTS5
  with `content='clothing_items'`. Returns `:ok` immediately if the item does
  not exist (graceful no-op for deleted items).
  """
  def upsert(item_id) do
    case Repo.get(Item, item_id) do
      nil ->
        :ok

      item ->
        Repo.transaction(fn ->
          # clothing_fts_meta tracks the title that was last indexed so we can
          # supply the correct old title to the FTS5 'delete' command, which
          # requires the exact indexed token values to remove them from the index.
          meta =
            Repo.query!(
              "SELECT indexed_title FROM clothing_fts_meta WHERE item_id = ? LIMIT 1",
              [item.id]
            )

          if meta.rows != [] do
            [[old_title]] = meta.rows

            Repo.query!(
              "INSERT INTO clothing_fts(clothing_fts, rowid, title) VALUES ('delete', ?, ?)",
              [item.id, old_title]
            )
          end

          Repo.query!(
            "INSERT INTO clothing_fts(rowid, title) VALUES (?, ?)",
            [item.id, item.title]
          )

          Repo.query!(
            "INSERT OR REPLACE INTO clothing_fts_meta(item_id, indexed_title) VALUES (?, ?)",
            [item.id, item.title]
          )
        end)

        :ok
    end
  end

  @doc """
  Returns the top `top_n` FTS5 matches for `query_text` as `[{item_id, score}]`,
  sorted by BM25 score ascending (most negative = most relevant first).

  Returns `[]` for an empty query string without hitting the DB.
  The caller is responsible for escaping the query before calling this function.
  """
  def search("", _top_n), do: []

  def search(query_text, top_n) do
    try do
      result =
        Repo.query!(
          "SELECT rowid, bm25(clothing_fts) AS score FROM clothing_fts WHERE clothing_fts MATCH ? ORDER BY score ASC LIMIT ?",
          [query_text, top_n]
        )

      Enum.map(result.rows, fn [rowid, score] ->
        {rowid, if(is_number(score), do: score * 1.0, else: 0.0)}
      end)
    rescue
      Exqlite.Error -> []
    end
  end
end
