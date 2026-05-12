defmodule ChatApp.ETL.Normalizer do
  @moduledoc false

  def normalize("ebay", raw) do
    %{
      source: "ebay",
      source_id: raw["itemId"],
      title: raw["title"],
      price: coerce_price(get_in(raw, ["price", "value"])),
      url: raw["itemWebUrl"],
      image_url: get_in(raw, ["image", "imageUrl"]),
      brand: nil,
      size: nil,
      condition_normalized: normalize_condition(raw["condition"]),
      last_scraped_at: DateTime.utc_now()
    }
  end

  def normalize("depop", raw) do
    %{
      source: "depop",
      source_id: raw["id"],
      title: raw["description"],
      price: coerce_price(raw["displayedPrice"]),
      url: if(raw["slug"], do: "https://depop.com/products/#{raw["slug"]}", else: nil),
      image_url: raw["pictureUrl"],
      brand: raw["brand"],
      size: Enum.at(raw["sizes"] || [], 0),
      condition_normalized: normalize_condition(nil),
      last_scraped_at: DateTime.utc_now()
    }
  end

  def normalize("poshmark", raw) do
    %{
      source: "poshmark",
      source_id: raw["source_id"],
      title: raw["title"],
      price: coerce_price(raw["price"]),
      url: raw["url"],
      image_url: raw["image_url"],
      brand: raw["brand"],
      size: raw["size"],
      condition_normalized: normalize_condition(raw["condition"]),
      last_scraped_at: DateTime.utc_now()
    }
  end

  @condition_map %{
    "New" => "new",
    "Like New" => "like_new",
    "Used" => "good"
  }

  defp normalize_condition(nil), do: "good"
  defp normalize_condition(raw), do: Map.get(@condition_map, raw, "good")

  defp coerce_price(nil), do: nil

  defp coerce_price(val) when is_binary(val) do
    val |> String.trim_leading("$") |> Decimal.new()
  end

  defp coerce_price(val) when is_integer(val), do: Decimal.new(val)
  defp coerce_price(val) when is_float(val), do: Decimal.from_float(val)
end
