defmodule SP0503SavedPageE2ETest do
  use ChatAppWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo

  setup do
    user = AccountsFixtures.user_fixture()
    %{user: user}
  end

  describe "SP-05-03 e2e" do
    test "saved_live_happy_path_renders_saved_cards", %{conn: conn, user: user} do
      item = item_fixture(%{source: "ebay"})
      assert {:ok, _} = Clothing.save_item(user.id, item.id, Decimal.new("45.00"))

      Repo.insert!(%PriceHistory{item_id: item.id, price: Decimal.new("45.00"), currency: "USD"})
      Repo.insert!(%PriceHistory{item_id: item.id, price: Decimal.new("38.00"), currency: "USD"})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/saved")

      assert html =~ item.title
      assert html =~ "↓15%"
      assert html =~ "Now $38"
      assert html =~ "target=\"_blank\""
    end

    test "saved_live_no_history_shows_message", %{conn: conn, user: user} do
      item = item_fixture(%{source: "depop"})
      assert {:ok, _} = Clothing.save_item(user.id, item.id, Decimal.new("45.00"))

      Repo.insert!(%PriceHistory{item_id: item.id, price: Decimal.new("45.00"), currency: "USD"})

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/saved")

      assert html =~ "No price history"
    end

    test "saved_live_removed_listing_shows_overlay", %{conn: conn, user: user} do
      item = item_fixture(%{source: "poshmark"})
      assert {:ok, _} = Clothing.save_item(user.id, item.id, Decimal.new("45.00"))

      Repo.update_all(
        from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
        set: [item_id: nil]
      )

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, ~p"/saved")

      assert html =~ "Listing Removed"
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Saved Page E2E Item #{System.unique_integer([:positive])}",
          brand: "Threadworks",
          price: Decimal.new("39.00"),
          url: "https://example.com/item-#{System.unique_integer([:positive])}",
          source: "ebay",
          source_id: "source-#{System.unique_integer([:positive])}"
        },
        overrides
      )

    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert!()
  end
end
