defmodule ChatApp.Clothing do
  @moduledoc """
  The Clothing context for managing second-hand items.
  Provides full-text search capabilities over the items.
  """

  import Ecto.Query, warn: false
  alias ChatApp.Repo
  alias ChatApp.Clothing.Item

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
    |> where([i], ilike(i.title, ^search_term) or ilike(i.brand, ^search_term) or ilike(i.description, ^search_term))
    |> Repo.all()
  end
end
