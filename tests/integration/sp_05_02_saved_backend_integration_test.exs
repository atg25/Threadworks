defmodule SP0502SavedBackendIntegrationTest do
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

  describe "SP-05-02 integration" do
    test "save_item_concurrent_calls_produce_single_row" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture()
      price = Decimal.new("19.90")

      task1 = Task.async(fn -> Clothing.save_item(user.id, item.id, price) end)
      task2 = Task.async(fn -> Clothing.save_item(user.id, item.id, price) end)

      _ = Task.await(task1, 5_000)
      _ = Task.await(task2, 5_000)

      count =
        Repo.aggregate(
          from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
          :count
        )

      assert count == 1
    end

    test "save_item_persists_price_with_two_decimal_precision" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "precision-item"})
      price_at_save = Decimal.new("19.9")

      assert {:ok, _} = Clothing.save_item(user.id, item.id, price_at_save)

      saved_price =
        Repo.one!(
          from(s in "saved_items",
            where: s.user_id == ^user.id and s.item_id == ^item.id,
            select: s.price_at_save
          )
        )

      assert Decimal.equal?(saved_price, Decimal.new("19.90"))
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Integration Test Item",
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
