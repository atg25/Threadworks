defmodule ChatApp.ETL.FTS5Index do
  @moduledoc false
  # Thin shim so EmbedWorker continues to call FTS5Index.upsert/1 by its
  # historical alias (ChatApp.ETL.FTS5Index) while the canonical implementation
  # lives in ChatApp.Search.FTS5Index. Consolidates both paths so they share
  # the delete-then-insert pattern and clothing_fts_meta state.
  defdelegate upsert(item_id), to: ChatApp.Search.FTS5Index
end
