defmodule ChatApp.Search.HybridEngine do
  @behaviour ChatApp.Search.HybridEngineBehaviour

  import Ecto.Query

  alias ChatApp.AI.Embedder
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Search.QueryProcessor
  alias ChatApp.Search.VectorStore

  @task_timeout 5_000
  @default_limit 10

  @doc """
  Searches for clothing items using RRF fusion of vector and FTS5 results.

  Returns `{:ok, items}` where each item is a `%ClothingItem{}` with `:rrf_score` set,
  sorted best-first. Returns `{:ok, []}` for an empty query. Propagates Embedder
  errors as `{:error, reason}`.
  """
  def search(query_text, opts \\ []) do
    limit = max(0, Keyword.get(opts, :limit, @default_limit))

    if String.trim(query_text) == "" do
      {:ok, []}
    else
      with {:ok, query_vector} <- Embedder.embed(query_text) do
        processed_query = QueryProcessor.process(query_text)

        vec_task = Task.Supervisor.async_nolink(ChatApp.TaskSupervisor, fn -> VectorStore.search(query_vector, 50) end)
        fts_task = Task.Supervisor.async_nolink(ChatApp.TaskSupervisor, fn -> FTS5Index.search(processed_query, 50) end)

        [vec_result, fts_result] =
          [vec_task, fts_task]
          |> Task.yield_many(@task_timeout)
          |> Enum.map(fn {task, result} ->
            case result do
              nil -> Task.shutdown(task, :brutal_kill); {:error, :timeout}
              {:ok, value} -> {:ok, value}
              {:exit, reason} -> {:error, reason}
            end
          end)

        with {:ok, vec_results} <- vec_result,
             {:ok, fts_results} <- fts_result do
          vec_ranks = to_rank_map(vec_results)
          fts_ranks = to_rank_map(fts_results)

          fused = rrf_fuse(vec_ranks, fts_ranks)

          top = Enum.take(fused, limit)

          if top == [] do
            {:ok, []}
          else
            ids = Enum.map(top, fn {id, _score} -> id end)
            score_map = Map.new(top)

            source = Keyword.get(opts, :source)
            max_price = Keyword.get(opts, :max_price)
            size = Keyword.get(opts, :size)

            item_map =
              Item
              |> where([i], i.id in ^ids)
              |> then(fn q ->
                if source, do: where(q, [i], i.source == ^to_string(source)), else: q
              end)
              |> then(fn q ->
                if max_price, do: where(q, [i], i.price <= ^max_price), else: q
              end)
              |> then(fn q ->
                if size,
                  do: where(q, [i], fragment("LOWER(?)", i.size) == fragment("LOWER(?)", ^size)),
                  else: q
              end)
              |> Repo.all()
              |> Map.new(fn i -> {i.id, i} end)

            ordered =
              ids
              |> Enum.flat_map(fn id ->
                case Map.get(item_map, id) do
                  nil -> []
                  item -> [%{item | rrf_score: score_map[id]}]
                end
              end)

            {:ok, ordered}
          end
        end
      end
    end
  end

  @doc """
  Fuses two rank maps using Reciprocal Rank Fusion (k=60).

  Each map is `%{item_id => rank}` where rank is 1-based. Returns
  `[{item_id, score}]` sorted DESC by score.
  """
  def rrf_fuse(vec_ranks, fts_ranks) do
    all_ids = Map.keys(vec_ranks) ++ Map.keys(fts_ranks)

    all_ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      score =
        Enum.sum(
          for {ranks, _label} <- [{vec_ranks, :vec}, {fts_ranks, :fts}],
              rank = Map.get(ranks, id),
              rank != nil do
            1.0 / (60 + rank)
          end
        )

      {id, score}
    end)
    |> Enum.sort_by(fn {_id, score} -> score end, :desc)
  end

  defp to_rank_map(results) do
    results
    |> Enum.with_index(1)
    |> Map.new(fn {{id, _score}, rank} -> {id, rank} end)
  end
end
