defmodule ChatApp.Clothing.ItemTest do
  use ExUnit.Case, async: true

  alias ChatApp.Clothing.Item

  defp valid_attrs do
    %{
      title: "Levi's 501 Jeans",
      brand: "Levi's",
      price: Decimal.new("45.99"),
      url: "https://www.ebay.com/itm/123456789"
    }
  end

  defp valid_attrs_with_etl_fields do
    Map.merge(valid_attrs(), %{
      source: "ebay",
      source_id: "v1|123456789|0",
      condition_normalized: "good",
      last_scraped_at: DateTime.utc_now()
    })
  end

  test "Item changeset accepts ETL fields" do
    changeset = %Item{} |> Item.changeset(valid_attrs_with_etl_fields())
    assert changeset.valid? == true
  end

  test "Item changeset casts all ETL fields into changes" do
    changeset = %Item{} |> Item.changeset(valid_attrs_with_etl_fields())
    assert Map.has_key?(changeset.changes, :source_id)
    assert Map.has_key?(changeset.changes, :condition_normalized)
    assert Map.has_key?(changeset.changes, :last_scraped_at)
  end

  test "Item changeset errors when source absent" do
    attrs = Map.delete(valid_attrs_with_etl_fields(), :source)
    changeset = %Item{} |> Item.changeset(attrs)
    assert changeset.valid? == false
    assert :source in Keyword.keys(changeset.errors)
  end
end
