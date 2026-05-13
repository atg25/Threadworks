defmodule SP0503SavedPageUnitTest do
  use ExUnit.Case, async: true

  describe "SP-05-03 unit" do
    test "format_price_delta_badge_renders_decrease" do
      delta =
        ChatAppWeb.Live.SavedLive.format_price_delta_badge(%{
          saved_price: Decimal.new("45.00"),
          current_price: Decimal.new("38.00")
        })

      rendered = Phoenix.HTML.safe_to_string(delta)

      assert rendered =~ "↓15%"
      assert rendered =~ "green"
    end

    test "format_price_delta_badge_renders_no_history" do
      delta = ChatAppWeb.Live.SavedLive.format_price_delta_badge(:no_history)
      rendered = Phoenix.HTML.safe_to_string(delta)

      assert rendered =~ "No price history"
    end

    test "saved_card_renders_listing_removed_when_item_nil" do
      saved_item = %{item: nil}
      html = ChatAppWeb.Live.SavedLive.render_saved_card(saved_item)
      rendered = Phoenix.HTML.safe_to_string(html)

      assert rendered =~ "Listing Removed"
    end
  end
end
