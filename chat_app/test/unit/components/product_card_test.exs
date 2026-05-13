defmodule ChatAppWeb.ProductCardTest do
  use ChatAppWeb.ConnCase, async: true

  @moduletag :unit

  import Phoenix.LiveViewTest
  import Phoenix.Component

  alias ChatApp.Clothing.Item
  alias ChatAppWeb.ProductCard

  defp item_fixture(overrides \\ %{}) do
    base = %Item{
      id: 1,
      title: "Levi's 501 Jeans",
      brand: "Levi's",
      size: "M",
      condition: "good",
      price: Decimal.new("45.00"),
      source: "ebay",
      url: "http://example.com/1",
      image_url: "https://example.com/img.jpg",
      rrf_score: 0.05
    }

    struct!(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # U1 — Image renders with onerror fallback attribute
  # ---------------------------------------------------------------------------

  test "U1: image renders with onerror fallback attribute" do
    html =
      render_component(&ProductCard.product_card/1,
        item: %Item{
          image_url: "https://example.com/img.jpg",
          title: "Jeans",
          size: "M",
          condition: "good",
          price: Decimal.new("30.00"),
          source: "ebay",
          url: "https://ebay.com/1"
        },
        reason: "",
        saved: false
      )

    assert html =~ ~s(src="https://example.com/img.jpg")
    assert html =~ "onerror"
    assert html =~ "/images/clothing_placeholder.svg"
  end

  # ---------------------------------------------------------------------------
  # U2 — Nil image_url falls back to placeholder directly in src
  # ---------------------------------------------------------------------------

  test "U2: nil image_url renders placeholder directly in src" do
    html =
      render_component(&ProductCard.product_card/1,
        item: %Item{
          image_url: nil,
          title: "Jeans",
          size: "M",
          condition: "good",
          price: Decimal.new("30.00"),
          source: "ebay",
          url: "https://ebay.com/1"
        },
        reason: "",
        saved: false
      )

    assert html =~ ~s(src="/images/clothing_placeholder.svg")
  end

  # ---------------------------------------------------------------------------
  # U3 — Unsaved state renders "Save" button with correct phx-click and phx-value
  # ---------------------------------------------------------------------------

  test "U3: unsaved state renders Save button with correct phx-click and phx-value" do
    item = item_fixture()

    html =
      render_component(&ProductCard.product_card/1,
        item: item,
        reason: "",
        saved: false
      )

    assert html =~ ~s(phx-click="save_item")
    assert html =~ ~s(phx-value-item-id="#{item.id}")
    assert html =~ "Save"
    refute html =~ "Saved"
  end

  # ---------------------------------------------------------------------------
  # U4 — Saved state renders "Saved" text without save phx-click
  # ---------------------------------------------------------------------------

  test "U4: saved state renders Saved text without save phx-click" do
    html =
      render_component(&ProductCard.product_card/1,
        item: item_fixture(),
        reason: "",
        saved: true
      )

    assert html =~ "Saved"
    refute html =~ ~s(phx-click="save_item")
  end

  # ---------------------------------------------------------------------------
  # U5 — "View" link has correct href, target, and rel
  # ---------------------------------------------------------------------------

  test "U5: View link has correct href, target=_blank, and rel=noopener noreferrer" do
    item = item_fixture(%{url: "https://ebay.com/item/99"})

    html =
      render_component(&ProductCard.product_card/1,
        item: item,
        reason: "",
        saved: false
      )

    assert html =~ ~s(href="https://ebay.com/item/99")
    assert html =~ ~s(target="_blank")
    assert html =~ ~s(rel="noopener noreferrer")
  end

  # ---------------------------------------------------------------------------
  # U6 — Reason text is rendered
  # ---------------------------------------------------------------------------

  test "U6: reason text is rendered" do
    html =
      render_component(&ProductCard.product_card/1,
        item: item_fixture(),
        reason: "Great for casual days",
        saved: false
      )

    assert html =~ "Great for casual days"
  end

  # ---------------------------------------------------------------------------
  # U7 — Condition displayed as human label, not raw atom string
  # ---------------------------------------------------------------------------

  test "U7: condition displayed as human label not raw atom string" do
    item = item_fixture(%{condition: "like_new"})

    html =
      render_component(&ProductCard.product_card/1,
        item: item,
        reason: "",
        saved: false
      )

    assert html =~ "Like new"
    refute html =~ "like_new"
  end

  # ---------------------------------------------------------------------------
  # U8 — condition_normalized takes precedence for badge display (spec field)
  # ---------------------------------------------------------------------------

  test "U8: condition_normalized drives badge when present" do
    item = item_fixture(%{condition_normalized: "good", condition: "raw_scraped_value"})

    html =
      render_component(&ProductCard.product_card/1,
        item: item,
        reason: "",
        saved: false
      )

    assert html =~ "Good"
    refute html =~ "raw_scraped_value"
  end

  # ---------------------------------------------------------------------------
  # U9 — javascript: href in item.url is sanitized (HEEx component path)
  # ---------------------------------------------------------------------------

  test "U9: javascript href in item.url is sanitized to # in HEEx component" do
    item = item_fixture(%{url: "javascript:alert(document.cookie)"})

    html =
      render_component(&ProductCard.product_card/1,
        item: item,
        reason: "",
        saved: false
      )

    refute html =~ "javascript:"
    assert html =~ ~s(href="#")
  end
end
