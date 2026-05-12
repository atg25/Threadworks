defmodule ChatApp.ETL.FixturesTest do
  use ExUnit.Case, async: true

  @fixtures_dir Path.join([__DIR__, "..", "..", "support", "http_mocks"])

  test "ebay_search_response.json is valid JSON with >= 20 itemSummaries" do
    path = Path.join(@fixtures_dir, "ebay_search_response.json")
    body = path |> File.read!() |> Jason.decode!()
    assert length(body["itemSummaries"]) >= 20
  end

  test "depop_search_response.json is valid JSON with >= 24 items" do
    path = Path.join(@fixtures_dir, "depop_search_response.json")
    body = path |> File.read!() |> Jason.decode!()
    assert length(body["products"]) >= 24
  end

  test "poshmark_search.html contains >= 20 elements with data-id attribute" do
    path = Path.join(@fixtures_dir, "poshmark_search.html")
    doc = path |> File.read!() |> Floki.parse_document!()
    assert length(Floki.find(doc, "[data-id]")) >= 20
  end

  test "openai_embeddings_response.json has 20 embeddings each of length 512" do
    path = Path.join(@fixtures_dir, "openai_embeddings_response.json")
    body = path |> File.read!() |> Jason.decode!()
    assert length(body["data"]) == 20

    Enum.each(body["data"], fn item ->
      assert length(item["embedding"]) == 512
    end)
  end
end
