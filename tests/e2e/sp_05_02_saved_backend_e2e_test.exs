defmodule SP0502SavedBackendE2ETest do
  use ChatApp.DataCase, async: false

  import Ecto.Query

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(ChatApp.Repo)
    :ok
  end

  describe "SP-05-02 e2e" do
    test "save_item_backend_happy_path" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture()
      price = Decimal.new("29.00")

      assert {:ok, _} = Clothing.save_item(user.id, item.id, price)

      saved =
        Repo.one!(
          from(s in "saved_items",
            where: s.user_id == ^user.id and s.item_id == ^item.id,
            select: %{user_id: s.user_id, item_id: s.item_id, price_at_save: s.price_at_save}
          )
        )

      assert saved.user_id == user.id
      assert saved.item_id == item.id
      assert Decimal.equal?(saved.price_at_save, Decimal.new("29.00"))
    end

    test "unsave_item_nonexistent_item_edge" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "missing-save-row"})

      count_before = Repo.aggregate("saved_items", :count)
      result = Clothing.unsave_item(user.id, item.id)
      count_after = Repo.aggregate("saved_items", :count)

      assert result in [:ok, {:ok, :deleted}]
      assert count_before == count_after
    end

    test "save_item_duplicate_rapid_edge" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "duplicate-rapid"})
      price = Decimal.new("49.00")

      assert {:ok, _} = Clothing.save_item(user.id, item.id, price)
      assert {:ok, _} = Clothing.save_item(user.id, item.id, price)

      count =
        Repo.aggregate(
          from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
          :count
        )

      assert count == 1
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "E2E Test Item",
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
