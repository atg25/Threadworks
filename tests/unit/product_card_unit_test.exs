defmodule ProductCardUnitTest do
  use ExUnit.Case, async: true

  describe "ProductCard unit tests" do
    test "product_card_formats_price_with_two_decimals" do
      # Expectation: format_price/1 returns string with two decimals
      price = Decimal.new("19.9")
      assert ChatAppWeb.Components.ProductCard.format_price(price) == "$19.90"
    end

    test "product_card_condition_label_humanized" do
      assert ChatAppWeb.Components.ProductCard.condition_label("good") == "Good"
    end

    test "product_card_uses_placeholder_when_image_missing" do
      item = %{image_url: nil}
      html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
      rendered = Phoenix.HTML.safe_to_string(html)
      assert rendered =~ "<img" and rendered =~ "/images/clothing_placeholder.svg"
    end

    test "product_card_includes_alt_text_and_external_link_attrs" do
      item = %{title: "Blue Jacket", url: "https://ex.com/1", image_url: nil}
      html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
      rendered = Phoenix.HTML.safe_to_string(html)
      assert rendered =~ "alt=\"Blue Jacket\""
      assert rendered =~ "target=\"_blank\"" and rendered =~ "rel=\"noopener noreferrer\""
    end

    test "product_card_escapes_reason_text_to_prevent_xss" do
      item = %{title: "T"}
      html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: "<script>alert(1)</script>"})
      rendered = Phoenix.HTML.safe_to_string(html)
      refute rendered =~ "<script>alert(1)</script>"
      assert rendered =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    end
  end
end
