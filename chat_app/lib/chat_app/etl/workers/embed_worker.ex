defmodule ChatApp.ETL.Workers.EmbedWorker do
  use Oban.Worker, queue: :embedder, max_attempts: 3

  import Ecto.Query

  alias ChatApp.Repo
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.AI.VectorCodec
  alias ChatApp.ETL.Embedder
  alias ChatApp.ETL.FTS5Index

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"item_ids" => item_ids}}) do
    items = Repo.all(from(i in ClothingItem, where: i.id in ^item_ids))

    if items == [] do
      :ok
    else
      embed_and_store(items)
    end
  end

  defp embed_and_store(items) do
    texts = Enum.map(items, &build_text/1)

    case Embedder.embed_batch(texts) do
      {:ok, embeddings} ->
        if length(embeddings) < length(items) do
          {:error, :embedding_count_mismatch}
        else
          Enum.zip(items, embeddings)
          |> Enum.each(fn {item, embedding} ->
            binary = VectorCodec.encode(embedding)

            Repo.update!(Ecto.Changeset.change(item, embedding: binary))

            Repo.query!("DELETE FROM clothing_vec WHERE rowid = ?", [item.id])

            Repo.query!(
              "INSERT INTO clothing_vec(rowid, embedding) VALUES (?, ?)",
              [item.id, {:blob, binary}]
            )

            FTS5Index.upsert(item.id)
          end)

          :ok
        end

      {:error, _} = err ->
        err
    end
  end

  defp build_text(item) do
    [item.title, item.brand, item.size, item.condition_normalized]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end
end
