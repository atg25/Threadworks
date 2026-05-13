defmodule SP0502SavedBackendUnitTest do
  use ChatApp.DataCase, async: false

  import Ecto.Query

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Clothing.SavedItem
  alias ChatApp.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(ChatApp.Repo)
    :ok
  end

  describe "SP-05-02 unit" do
    test "save_item_inserts_idempotently" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture()
      price = Decimal.new("39.00")

      assert {:ok, _} = Clothing.save_item(user.id, item.id, price)
      assert {:ok, _} = Clothing.save_item(user.id, item.id, price)

      count =
        Repo.aggregate(
          from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
          :count
        )

      assert count == 1
    end

    test "unsave_item_deletes_row_or_noop" do
      user = AccountsFixtures.user_fixture()
      item = item_fixture()

      Repo.query!(
        "INSERT INTO saved_items (user_id, item_id, price_at_save, inserted_at) VALUES (?, ?, ?, ?)",
        [user.id, item.id, "20.00", "2026-05-13 00:00:00"]
      )

      assert :ok = Clothing.unsave_item(user.id, item.id)

      assert is_nil(Repo.get_by(SavedItem, user_id: user.id, item_id: item.id))
    end

    test "list_saved_item_ids_returns_mapset_of_integers" do
      user = AccountsFixtures.user_fixture()
      item1 = item_fixture(%{source_id: "saved-ids-1"})
      item2 = item_fixture(%{source_id: "saved-ids-2"})

      Repo.query!(
        "INSERT INTO saved_items (user_id, item_id, inserted_at) VALUES (?, ?, ?), (?, ?, ?)",
        [user.id, item1.id, "2026-05-13 00:00:00", user.id, item2.id, "2026-05-13 00:00:01"]
      )

      assert Clothing.list_saved_item_ids(user.id) == MapSet.new([item1.id, item2.id])
    end

    test "get_price_delta_returns_no_history_for_one_row" do
      item = item_fixture(%{source_id: "delta-one-row"})

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("50.00"),
        currency: "USD"
      })

      assert Clothing.get_price_delta(item.id) == :no_history
    end

    test "get_price_delta_uses_two_most_recent_rows" do
      item = item_fixture(%{source_id: "delta-two-recent"})

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("50.00"),
        currency: "USD",
        inserted_at: ~U[2026-05-13 09:00:00.000000Z]
      })

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("45.00"),
        currency: "USD",
        inserted_at: ~U[2026-05-13 10:00:00.000000Z]
      })

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("40.00"),
        currency: "USD",
        inserted_at: ~U[2026-05-13 11:00:00.000000Z]
      })

      expected = Decimal.new("-11.11111111111111111111")
      assert Decimal.equal?(Clothing.get_price_delta(item.id), expected)
    end

    test "get_price_delta_handles_zero_saved_price_gracefully" do
      item = item_fixture(%{source_id: "delta-zero-denominator"})

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("0.00"),
        currency: "USD",
        inserted_at: ~U[2026-05-13 10:00:00.000000Z]
      })

      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.new("0.00"),
        currency: "USD",
        inserted_at: ~U[2026-05-13 11:00:00.000000Z]
      })

      result = Clothing.get_price_delta(item.id)
      assert result in [:no_history, :free]
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Unit Test Item",
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
