defmodule ChatApp.ETL.Deduplicator do
  alias ChatApp.Repo
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.Clothing.PriceHistory

  def upsert(attrs) do
    changeset = ClothingItem.changeset(%ClothingItem{}, attrs)
    price = Map.get(attrs, :price)

    Repo.transaction(fn ->
      case Repo.insert(changeset,
             on_conflict:
               {:replace, [:price, :last_scraped_at, :image_url, :size, :condition_normalized]},
             conflict_target: [:source, :source_id]
           ) do
        {:ok, item} ->
          case Repo.insert(%PriceHistory{item_id: item.id, price: price}) do
            {:ok, _ph} -> item
            {:error, ph_cs} -> Repo.rollback(ph_cs)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def upsert_all(items) do
    results = Enum.map(items, &upsert/1)

    case Enum.find(results, fn r -> match?({:error, _}, r) end) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, item} -> item end)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
