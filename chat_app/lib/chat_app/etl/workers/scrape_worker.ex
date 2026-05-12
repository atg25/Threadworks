defmodule ChatApp.ETL.Workers.ScrapeWorker do
  use Oban.Worker, queue: :scraper, max_attempts: 3

  alias ChatApp.ETL.Sources.{Ebay, Depop, Poshmark}
  alias ChatApp.ETL.Normalizer
  alias ChatApp.ETL.Deduplicator
  alias ChatApp.ETL.Workers.EmbedWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"queries" => queries}}) when is_list(queries) do
    for source <- ["ebay", "depop", "poshmark"],
        query <- queries do
      %{"source" => source, "query" => query}
      |> __MODULE__.new()
      |> Oban.insert!()
    end

    :ok
  end

  def perform(%Oban.Job{args: %{"source" => source, "query" => query}}) do
    case fetch(source, query) do
      {:ok, raw_items} ->
        normalized = Enum.map(raw_items, &Normalizer.normalize(source, &1))

        case Deduplicator.upsert_all(normalized) do
          {:ok, items} ->
            items
            |> Enum.chunk_every(20)
            |> Enum.each(fn chunk ->
              %{"item_ids" => Enum.map(chunk, & &1.id)}
              |> EmbedWorker.new()
              |> Oban.insert!()
            end)

            :ok

          {:error, _} = err ->
            err
        end

      {:error, _} = err ->
        err
    end
  end

  defp fetch("ebay", query), do: Ebay.fetch_items(query)
  defp fetch("depop", query), do: Depop.fetch_items(query)
  defp fetch("poshmark", query), do: Poshmark.fetch_items(query)
end
