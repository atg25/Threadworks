defmodule ChatApp.Clothing.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "clothing_items" do
    field(:title, :string)
    field(:brand, :string)
    field(:size, :string)
    field(:condition, :string)
    field(:price, :decimal)
    field(:url, :string)
    field(:image_url, :string)
    field(:description, :string)
    # Placeholder for sqlite-vec binary vector
    field(:embedding, :binary)
    field(:source, :string)
    field(:source_id, :string)
    field(:condition_normalized, :string)
    field(:last_scraped_at, :utc_datetime)
    field(:rrf_score, :float, virtual: true)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :title,
      :brand,
      :size,
      :condition,
      :price,
      :url,
      :image_url,
      :description,
      :embedding,
      :source,
      :source_id,
      :condition_normalized,
      :last_scraped_at
    ])
    |> validate_required([:title, :price, :url, :source])
  end
end
