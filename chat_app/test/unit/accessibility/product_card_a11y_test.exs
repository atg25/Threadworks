defmodule ChatAppWeb.ProductCardA11yTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias ChatApp.Clothing.Item

  test "product card has accessible attributes" do
    item = %Item{
      id: 1,
      title: "A Jacket",
      image_url: "https://example.com/img.jpg",
      url: "https://example.com/view/1",
      price: Decimal.new("19.99"),
      source: "amazon",
      condition: "new"
    }

    html =
      render_component(&ChatAppWeb.ProductCard.product_card/1,
        item: item,
        reason: "Nice",
        saved: false
      )

    # Parse with Floki to assert accessibility attributes
    {:ok, doc} = Floki.parse_document(html)

    # images must have alt text
    assert Floki.attribute(doc, "img", "alt") |> Enum.any?()

    # external links should have target and rel
    assert Floki.find(doc, "a[target=\"_blank\"]") |> Enum.any?()
    assert Floki.find(doc, "a[rel=\"noopener noreferrer\"]") |> Enum.any?()

    # save button should expose aria-label when present
    assert Floki.attribute(doc, "button", "aria-label") |> Enum.any?()
  end
end
