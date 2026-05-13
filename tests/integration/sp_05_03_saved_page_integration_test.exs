defmodule SP0503SavedPageIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  setup do
    user = AccountsFixtures.user_fixture()

    ebay_item = item_fixture(%{source: "ebay", source_id: "saved-page-ebay"})
    depop_item = item_fixture(%{source: "depop", source_id: "saved-page-depop"})

    assert {:ok, _} = Clothing.save_item(user.id, ebay_item.id, Decimal.new("45.00"))
    assert {:ok, _} = Clothing.save_item(user.id, depop_item.id, Decimal.new("40.00"))

    %{user: user, ebay_item: ebay_item, depop_item: depop_item}
  end

  describe "SP-05-03 integration" do
    test "saved_live_mount_loads_saved_items_and_defaults", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/saved")

      assert is_list(view.assigns.saved_items)
      assert view.assigns.filter_source == "All"
      assert view.assigns.sort_by == "Recently saved"
    end

    test "saved_live_filters_by_source", %{
      conn: conn,
      user: user,
      ebay_item: ebay_item,
      depop_item: depop_item
    } do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/saved")

      _html =
        view
        |> element("form[phx-change=filter]")
        |> render_change(%{"filter_source" => "Depop"})

      assert render(view) =~ depop_item.title
      refute render(view) =~ ebay_item.title
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Saved Page Item #{System.unique_integer([:positive])}",
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
