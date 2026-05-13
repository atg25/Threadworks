defmodule ChatApp.Clothing do
  @moduledoc """
  The Clothing context for managing second-hand items.
  Provides full-text search capabilities over the items.
  """

  import Ecto.Query, warn: false
  alias ChatApp.Repo
  alias ChatApp.Clothing.Item
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Clothing.SavedItem

  @doc """
  Returns the list of items.
  """
  def list_items do
    Repo.all(Item)
  end

  @doc """
  Gets a single item.
  """
  def get_item!(id), do: Repo.get!(Item, id)

  @doc """
  Gets a single item, returns nil if not found.
  """
  def get_item(id), do: Repo.get(Item, id)

  @doc """
  Creates an item.
  """
  def create_item(attrs \\ %{}) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end

  def search_hybrid(query_text, opts \\ []) do
    ChatApp.Search.HybridEngine.search(query_text, opts)
  end

  @doc """
  Searches for items using simplistic text matching (to be upgraded to FTS / Vector later).
  """
  def search_items(query) do
    search_term = "%#{query}%"

    Item
    |> where(
      [i],
      ilike(i.title, ^search_term) or ilike(i.brand, ^search_term) or
        ilike(i.description, ^search_term)
    )
    |> Repo.all()
  end

  def save_item(user_id, item_id, price_at_save)
      when is_integer(user_id) and is_integer(item_id) and is_struct(price_at_save, Decimal) do
    %SavedItem{}
    |> SavedItem.changeset(%{
      user_id: user_id,
      item_id: item_id,
      price_at_save: Decimal.round(price_at_save, 2)
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :item_id])
  end

  def unsave_item(user_id, item_id) when is_integer(user_id) and is_integer(item_id) do
    from(s in SavedItem, where: s.user_id == ^user_id and s.item_id == ^item_id)
    |> Repo.delete_all()

    :ok
  end

  def list_saved_items(user_id) when is_integer(user_id) do
    SavedItem
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> preload(:item)
    |> Repo.all()
  end

  def list_saved_item_ids(user_id) when is_integer(user_id) do
    SavedItem
    |> where([s], s.user_id == ^user_id)
    |> select([s], s.item_id)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @doc """
  Returns the percent change between the two most recent price_history rows.

  Returns `:no_history` when fewer than two rows exist, or when the previous
  price is zero and a percent delta cannot be computed safely.

  When a delta is returned, it is rounded to 20 decimal places to provide a
  stable, deterministic Decimal value.
  """
  def get_price_delta(item_id) when is_integer(item_id) do
    case two_most_recent_prices(item_id) do
      [latest, previous] ->
        if Decimal.equal?(previous.price, Decimal.new("0")) do
          :no_history
        else
          latest.price
          |> Decimal.sub(previous.price)
          |> Decimal.div(previous.price)
          |> Decimal.mult(Decimal.new("100"))
          |> Decimal.round(20)
        end

      _ ->
        :no_history
    end
  end

  defp two_most_recent_prices(item_id) do
    PriceHistory
    |> where([ph], ph.item_id == ^item_id)
    |> order_by([ph], desc: ph.inserted_at, desc: ph.id)
    |> limit(2)
    |> Repo.all()
  end
end
