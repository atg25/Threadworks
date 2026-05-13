defmodule ProductCardE2ETest do
  use ExUnit.Case, async: true

  test "product_card_render_happy_path_contains_all_user_visible_fields" do
    item = %{
      id: 1,
      title: "Nice Jacket",
      brand: "BrandX",
      size: "M",
      condition_normalized: "good",
      price: Decimal.new("19.9"),
      source: "eBay",
      reason: "Good match",
      image_url: nil,
      url: "https://example.com/1"
    }

    html =
      ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: item.reason})

    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "Nice Jacket"
    assert rendered =~ "BrandX"
    assert rendered =~ "$19.90"
    assert rendered =~ "eBay"
    assert rendered =~ "Good match"
    assert rendered =~ "Save"
    assert rendered =~ "target=\"_blank\""
  end

  test "product_card_handles_unknown_condition_without_crash" do
    item = %{condition_normalized: "mystery", title: "Unknown"}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "Mystery" or rendered =~ "Unknown"
  end

  test "product_card_image_load_failure_shows_placeholder" do
    item = %{image_url: "http://invalid/404.png", title: "T"}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "/images/clothing_placeholder.svg" or rendered =~ "onerror"
  end
end
