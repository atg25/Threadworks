defmodule ChatApp.ETL.DeduplicatorTest do
  use ChatApp.DataCase, async: false

  alias ChatApp.ETL.Deduplicator
  alias ChatApp.Clothing.Item, as: ClothingItem
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        source: "ebay",
        source_id: "v1|#{System.unique_integer([:positive])}",
        title: "Vintage Levi's 501",
        brand: "Levi's",
        price: Decimal.new("24.99"),
        url: "https://ebay.com/item/123",
        condition_normalized: "good",
        last_scraped_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      overrides
    )
  end

  defp build_items(n) do
    Enum.map(1..n, fn i ->
      valid_attrs(%{source_id: "v1|#{i}", title: "Item #{i}"})
    end)
  end

  defp count_items, do: Repo.aggregate(ClothingItem, :count)
  defp count_price_history, do: Repo.aggregate(PriceHistory, :count)

  defp fetch_all_last_scraped_at do
    Repo.all(from(i in ClothingItem, select: i.last_scraped_at))
  end

  # ---------------------------------------------------------------------------
  # Unit Tests — single upsert
  # ---------------------------------------------------------------------------

  test "upsert/1 inserts new item and returns {:ok, %ClothingItem{}}" do
    assert {:ok, %ClothingItem{id: id}} = Deduplicator.upsert(valid_attrs())
    assert is_integer(id)
    refute is_nil(id)
  end

  test "upsert/1 on conflict replaces price" do
    attrs = valid_attrs(%{source_id: "v1|conflict-price", price: Decimal.new("10.00")})
    assert {:ok, _} = Deduplicator.upsert(attrs)

    assert {:ok, item} =
             Deduplicator.upsert(Map.put(attrs, :price, Decimal.new("15.00")))

    assert item.price == Decimal.new("15.00")
  end

  test "upsert/1 on conflict replaces image_url, size, condition_normalized, last_scraped_at" do
    attrs =
      valid_attrs(%{
        source_id: "v1|conflict-fields",
        image_url: "https://old.example.com/img.jpg",
        size: "S",
        condition_normalized: "good",
        last_scraped_at: ~U[2026-01-01 00:00:00Z]
      })

    assert {:ok, _} = Deduplicator.upsert(attrs)

    new_scraped_at = ~U[2026-06-01 00:00:00Z]

    updated_attrs =
      Map.merge(attrs, %{
        image_url: "https://new.example.com/img.jpg",
        size: "L",
        condition_normalized: "like_new",
        last_scraped_at: new_scraped_at
      })

    assert {:ok, item} = Deduplicator.upsert(updated_attrs)

    assert item.image_url == "https://new.example.com/img.jpg"
    assert item.size == "L"
    assert item.condition_normalized == "like_new"
    assert item.last_scraped_at == new_scraped_at
  end

  test "upsert/1 on conflict does NOT replace title" do
    attrs = valid_attrs(%{source_id: "v1|conflict-title", title: "Original Title"})
    assert {:ok, _} = Deduplicator.upsert(attrs)

    assert {:ok, _} = Deduplicator.upsert(Map.put(attrs, :title, "Changed Title"))

    item = Repo.get_by!(ClothingItem, source: attrs.source, source_id: attrs.source_id)
    assert item.title == "Original Title"
  end

  test "upsert/1 second call same source+source_id does not increase item count" do
    attrs = valid_attrs(%{source_id: "v1|idempotent"})
    assert {:ok, _} = Deduplicator.upsert(attrs)
    count = count_items()
    assert {:ok, _} = Deduplicator.upsert(attrs)
    assert count_items() == count
  end

  test "upsert/1 does not raise on duplicate source+source_id" do
    attrs = valid_attrs(%{source_id: "v1|no-raise"})
    assert {:ok, _} = Deduplicator.upsert(attrs)
    assert {:ok, _} = Deduplicator.upsert(attrs)
  end

  # ---------------------------------------------------------------------------
  # Unit Tests — price history
  # ---------------------------------------------------------------------------

  test "upsert/1 writes one PriceHistory row on first insert" do
    assert {:ok, _} = Deduplicator.upsert(valid_attrs())
    assert count_price_history() == 1
  end

  test "upsert/1 writes PriceHistory row even when price unchanged" do
    attrs = valid_attrs(%{source_id: "v1|ph-unchanged"})
    assert {:ok, _} = Deduplicator.upsert(attrs)
    assert {:ok, _} = Deduplicator.upsert(attrs)
    assert count_price_history() == 2
  end

  test "upsert/1 writes PriceHistory row when price changes" do
    attrs = valid_attrs(%{source_id: "v1|ph-changed", price: Decimal.new("10.00")})
    assert {:ok, _} = Deduplicator.upsert(attrs)
    assert {:ok, _} = Deduplicator.upsert(Map.put(attrs, :price, Decimal.new("12.00")))

    assert count_price_history() == 2

    latest =
      Repo.one(from(ph in PriceHistory, order_by: [desc: ph.inserted_at], limit: 1))

    assert latest.price == Decimal.new("12.00")
  end

  test "PriceHistory row references correct item_id" do
    assert {:ok, item} = Deduplicator.upsert(valid_attrs())
    assert %PriceHistory{} = Repo.get_by!(PriceHistory, item_id: item.id)
  end

  test "upsert/1 handles nil image_url without constraint error" do
    attrs = valid_attrs() |> Map.put(:image_url, nil)
    assert {:ok, %ClothingItem{image_url: nil}} = Deduplicator.upsert(attrs)
  end

  # ---------------------------------------------------------------------------
  # Integration Tests — batch upsert
  # ---------------------------------------------------------------------------

  test "upsert_all/1 on N items: item count == N, price_history count == N" do
    assert {:ok, _items} = Deduplicator.upsert_all(build_items(20))
    assert count_items() == 20
    assert count_price_history() == 20
  end

  test "upsert_all/1 on N items twice: item count unchanged, price_history count == 2N" do
    items = build_items(20)
    assert {:ok, _} = Deduplicator.upsert_all(items)
    assert {:ok, _} = Deduplicator.upsert_all(items)
    assert count_items() == 20
    assert count_price_history() == 40
  end

  test "upsert_all/1 returns list of %ClothingItem{} with DB-assigned ids" do
    assert {:ok, items} = Deduplicator.upsert_all(build_items(5))
    assert length(items) == 5
    assert Enum.all?(items, fn item -> is_integer(item.id) and not is_nil(item.id) end)
  end

  test "upsert_all/1 second run updates last_scraped_at on all items" do
    base_time = ~U[2026-01-01 00:00:00Z]

    items =
      Enum.map(1..5, fn i ->
        valid_attrs(%{source_id: "v1|ts-#{i}", last_scraped_at: base_time})
      end)

    assert {:ok, _} = Deduplicator.upsert_all(items)
    t1 = fetch_all_last_scraped_at()

    later_time = ~U[2026-06-01 00:00:00Z]

    updated_items =
      Enum.map(items, fn item -> Map.put(item, :last_scraped_at, later_time) end)

    assert {:ok, _} = Deduplicator.upsert_all(updated_items)
    t2 = fetch_all_last_scraped_at()

    Enum.zip(t1, t2)
    |> Enum.each(fn {old_ts, new_ts} ->
      assert DateTime.compare(new_ts, old_ts) == :gt
    end)
  end
end
