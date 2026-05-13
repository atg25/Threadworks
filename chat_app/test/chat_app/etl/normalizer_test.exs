defmodule ChatApp.ETL.NormalizerTest do
  use ExUnit.Case, async: true

  alias ChatApp.ETL.Normalizer

  defp ebay_raw_item do
    %{
      "itemId" => "v1|123456789|0",
      "title" => "Levi's 501 Original Fit Jeans",
      "price" => %{"value" => "45.99", "currency" => "USD"},
      "condition" => "Used",
      "image" => %{"imageUrl" => "https://i.ebayimg.com/images/g/abc/s-l225.jpg"},
      "itemWebUrl" => "https://www.ebay.com/itm/123456789"
    }
  end

  defp depop_raw_item do
    %{
      "id" => "abc123",
      "description" => "Great vintage Levi's jeans in good condition",
      "displayedPrice" => 25.0,
      "brand" => "Levi's",
      "sizes" => ["M"],
      "pictureUrl" => "https://d2h1pu99sxkfvn.cloudfront.net/b0/abc123/P0.jpg",
      "slug" => "abc123-levis-jeans"
    }
  end

  defp poshmark_raw_item do
    %{
      "source_id" => "pm789",
      "title" => "Nike Air Force 1",
      "price" => "85.00",
      "brand" => "Nike",
      "size" => "10",
      "image_url" => "https://di2ponv0v5otw.cloudfront.net/posts/img/pm789.jpg",
      "url" => "https://poshmark.com/listing/Nike-Air-Force-1-pm789",
      "condition" => "Used"
    }
  end

  # --- Field mapping tests ---

  test "normalize/2 eBay maps all required fields" do
    result = Normalizer.normalize("ebay", ebay_raw_item())
    assert result.source == "ebay"
    assert result.source_id == "v1|123456789|0"
    assert result.title == "Levi's 501 Original Fit Jeans"
    assert %Decimal{} = result.price
    assert result.url == "https://www.ebay.com/itm/123456789"
    assert result.image_url == "https://i.ebayimg.com/images/g/abc/s-l225.jpg"
    refute is_nil(result.source)
  end

  test "normalize/2 Depop maps all required fields" do
    result = Normalizer.normalize("depop", depop_raw_item())
    assert result.source == "depop"
    assert result.source_id == "abc123"
    assert result.url == "https://depop.com/products/abc123-levis-jeans"
    assert result.brand == "Levi's"
    assert result.size == "M"
  end

  test "normalize/2 Poshmark maps all required fields" do
    result = Normalizer.normalize("poshmark", poshmark_raw_item())
    assert result.source == "poshmark"
    assert result.source_id == "pm789"
    assert result.title == "Nike Air Force 1"
    assert %Decimal{} = result.price
    assert result.url == "https://poshmark.com/listing/Nike-Air-Force-1-pm789"
    assert result.image_url == "https://di2ponv0v5otw.cloudfront.net/posts/img/pm789.jpg"
  end

  test "Depop nil slug returns url: nil" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "slug", nil))
    assert result.url == nil
  end

  # --- Condition normalization tests ---

  test ~s(eBay "New" → condition_normalized: "new") do
    result = Normalizer.normalize("ebay", Map.put(ebay_raw_item(), "condition", "New"))
    assert result.condition_normalized == "new"
  end

  test ~s(eBay "Like New" → condition_normalized: "like_new") do
    result = Normalizer.normalize("ebay", Map.put(ebay_raw_item(), "condition", "Like New"))
    assert result.condition_normalized == "like_new"
  end

  test ~s(eBay "Used" → condition_normalized: "good") do
    result = Normalizer.normalize("ebay", Map.put(ebay_raw_item(), "condition", "Used"))
    assert result.condition_normalized == "good"
  end

  test "Unrecognized condition defaults to \"good\"" do
    result = Normalizer.normalize("ebay", Map.put(ebay_raw_item(), "condition", "Refurbished"))
    assert result.condition_normalized == "good"
  end

  test "Depop condition always normalizes to \"good\"" do
    result = Normalizer.normalize("depop", depop_raw_item())
    assert result.condition_normalized == "good"
  end

  test ~s(Poshmark "Like New" text → condition_normalized: "like_new") do
    result =
      Normalizer.normalize("poshmark", Map.put(poshmark_raw_item(), "condition", "Like New"))

    assert result.condition_normalized == "like_new"
  end

  test "Poshmark nil condition → \"good\"" do
    result = Normalizer.normalize("poshmark", Map.put(poshmark_raw_item(), "condition", nil))
    assert result.condition_normalized == "good"
  end

  # --- Nil and edge case tests ---

  test "nil image_url preserved as nil on eBay path" do
    raw = put_in(ebay_raw_item(), ["image", "imageUrl"], nil)
    result = Normalizer.normalize("ebay", raw)
    assert result.image_url == nil
  end

  test "nil image_url preserved as nil on Depop path" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "pictureUrl", nil))
    assert result.image_url == nil
  end

  test "Depop sizes: [] returns size: nil" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "sizes", []))
    assert result.size == nil
  end

  test "Depop sizes: nil returns size: nil" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "sizes", nil))
    assert result.size == nil
  end

  test "brand field is present in output (may be nil) on eBay path" do
    result = Normalizer.normalize("ebay", ebay_raw_item())
    assert Map.has_key?(result, :brand) == true
  end

  # --- Price coercion tests ---

  test "price as string coerces to Decimal" do
    raw = put_in(ebay_raw_item(), ["price", "value"], "12.99")
    result = Normalizer.normalize("ebay", raw)
    assert result.price == Decimal.new("12.99")
  end

  test "price as integer 0 coerces to Decimal" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "displayedPrice", 0))
    assert result.price == Decimal.new("0")
  end

  test "price as float coerces to Decimal" do
    result = Normalizer.normalize("depop", Map.put(depop_raw_item(), "displayedPrice", 9.99))
    assert is_struct(result.price, Decimal) == true
  end

  test "price nil returns nil" do
    raw = put_in(ebay_raw_item(), ["price", "value"], nil)
    result = Normalizer.normalize("ebay", raw)
    assert result.price == nil
  end

  # --- Timestamp and unknown source tests ---

  test "last_scraped_at is a UTC DateTime struct" do
    result = Normalizer.normalize("ebay", ebay_raw_item())
    assert is_struct(result.last_scraped_at, DateTime) == true
    assert result.last_scraped_at.time_zone == "Etc/UTC"
  end

  test "normalize/2 unknown source raises FunctionClauseError" do
    assert_raise FunctionClauseError, fn ->
      Normalizer.normalize("etsy", %{})
    end
  end
end
