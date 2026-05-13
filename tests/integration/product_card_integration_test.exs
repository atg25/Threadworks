defmodule ProductCardIntegrationTest do
  use ExUnit.Case, async: true
  # Integration-level tests; these will exercise rendered component markup

  test "product_card_renders_save_button_state_based_on_saved_flag - unsaved" do
    item = %{id: 123, title: "T", image_url: nil}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "Save"
    assert rendered =~ "phx-value-item-id=\"123\""
  end

  test "product_card_renders_save_button_state_based_on_saved_flag - saved" do
    item = %{id: 123, title: "T", image_url: nil}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: true, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "Saved"
  end

  test "product_card_renders_source_badge_and_view_link" do
    item = %{source: "eBay", url: "https://ebay.com/item", title: "T", image_url: nil}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    assert rendered =~ "eBay"
    assert rendered =~ "target=\"_blank\"" and rendered =~ "rel=\"noopener noreferrer\""
  end
end
