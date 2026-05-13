defmodule ProductCardSafetyTest do
  use ExUnit.Case, async: true

  test "sanitizes javascript href and image src" do
    item = %{
      id: 1,
      title: "Bad",
      url: "javascript:alert(1)",
      image_url: "javascript:alert(1)",
      price: Decimal.new("1.0"),
      source: "X"
    }

    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    refute rendered =~ "javascript:alert(1)"
    assert rendered =~ "/images/clothing_placeholder.svg"
    # href should be sanitized to # or safe fallback
    assert rendered =~ "href=\"#\"" or rendered =~ "href=\"/"
  end

  test "escapes item id in attribute" do
    item = %{id: "<bad>1&", title: "T", image_url: nil}
    html = ChatAppWeb.Components.ProductCard.render(%{item: item, saved: false, reason: ""})
    rendered = Phoenix.HTML.safe_to_string(html)
    refute rendered =~ "<bad>1&"
    assert rendered =~ "phx-value-item-id=\"&lt;bad&gt;1&amp;\""
  end
end
