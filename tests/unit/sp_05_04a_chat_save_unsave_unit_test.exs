defmodule SP0504aChatSaveUnsaveUnitTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  describe "SP-05-04a unit" do
    test "chat_live_mount_initializes_saved_item_ids_and_status", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "sp-05-04a-unit-mount"})
      assert {:ok, _} = Clothing.save_item(user.id, item.id, Decimal.new("42.00"))

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")
      assigns = live_assigns(view)

      assert assigns.saved_item_ids == MapSet.new([item.id])
      assert assigns.rag_status == :idle
      assert Map.has_key?(assigns, :last_scraped_at)
    end

    test "chat_live_sets_rag_status_assigns", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      assert live_assigns(view).rag_status == :idle
    end
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "SP-05-04a Unit Item #{System.unique_integer([:positive])}",
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
