defmodule ChatApp.Search.FTS5IndexIntegrationTest do
  use ChatApp.DataCase, async: false

  @moduletag :integration

  alias ChatApp.Search.FTS5Index
  alias ChatApp.Search.QueryProcessor
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  # ---------------------------------------------------------------------------
  # I-01 — upsert/1 creates a searchable FTS entry for a new item by title
  # ---------------------------------------------------------------------------

  test "I-01: upsert/1 creates a searchable FTS entry for a new item by title" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Vintage Levi Denim Jacket",
          price: "25.00",
          url: "http://e.com/1",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    result = FTS5Index.search("levi", 5)

    assert Enum.any?(result, fn {id, score} ->
             id == item.id and score < 0
           end),
           "expected item_id #{item.id} with negative score in results, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-02 — upsert/1 replaces (not duplicates) an existing FTS entry after title change
  # ---------------------------------------------------------------------------

  test "I-02: upsert/1 replaces an existing FTS entry after title change — no duplicate" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Blue Jacket",
          price: "20.00",
          url: "http://e.com/2",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    {:ok, item} =
      item
      |> Item.changeset(%{title: "Red Jacket"})
      |> Repo.update()

    :ok = FTS5Index.upsert(item.id)

    red_results = FTS5Index.search("red jacket", 5)
    blue_results = FTS5Index.search("blue jacket", 5)
    red_count = FTS5Index.search("red jacket", 10)

    assert Enum.any?(red_results, fn {id, _} -> id == item.id end),
           "expected item_id #{item.id} in 'red jacket' results, got: #{inspect(red_results)}"

    refute Enum.any?(blue_results, fn {id, _} -> id == item.id end),
           "expected item_id #{item.id} NOT in 'blue jacket' results (stale), got: #{inspect(blue_results)}"

    count = Enum.count(red_count, fn {id, _} -> id == item.id end)

    assert count == 1,
           "expected exactly 1 FTS entry for item_id #{item.id}, got #{count}: #{inspect(red_count)}"
  end

  # ---------------------------------------------------------------------------
  # I-03 — upsert/1 for a non-existent item_id returns :ok without crashing
  # ---------------------------------------------------------------------------

  test "I-03: upsert/1 for a non-existent item_id returns :ok without crashing" do
    assert :ok = FTS5Index.upsert(999_999)
  end

  # ---------------------------------------------------------------------------
  # I-04 — BM25 scores are negative floats; most relevant item appears first (ASC sort)
  # ---------------------------------------------------------------------------

  test "I-04: BM25 scores are negative floats; most relevant item appears first (ASC sort)" do
    {:ok, item1} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Levi Denim Jacket",
          price: "30.00",
          url: "http://e.com/3",
          source: "ebay"
        })
      )

    {:ok, item2} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Silk Evening Dress",
          price: "50.00",
          url: "http://e.com/4",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item1.id)
    :ok = FTS5Index.upsert(item2.id)

    result = FTS5Index.search("levi denim", 10)

    assert length(result) >= 1,
           "expected at least one result, got: #{inspect(result)}"

    [{first_id, score1} | _] = result

    assert first_id == item1.id,
           "expected item1 (#{item1.id}) first, got: #{first_id}"

    assert score1 < 0,
           "expected negative BM25 score, got: #{score1}"

    Enum.each(result, fn {_id, score} ->
      assert is_float(score),
             "expected float score, got: #{inspect(score)}"
    end)

    # If item2 appears, item1 must still be more relevant (lower score = more negative)
    case Enum.find(result, fn {id, _} -> id == item2.id end) do
      {_, score2} ->
        assert score1 < score2,
               "expected item1 score (#{score1}) more negative than item2 score (#{score2})"

      nil ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # I-05 — search/2 returns [] for a query with no matching items
  # ---------------------------------------------------------------------------

  test "I-05: search/2 returns [] for a query with no matching items" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Nike Running Shorts",
          price: "15.00",
          url: "http://e.com/5",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    result = FTS5Index.search("xyzzy plugh", 10)

    assert result == [],
           "expected empty list for non-matching query, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-06 — search/2 respects top_n
  # ---------------------------------------------------------------------------

  test "I-06: search/2 respects top_n limit" do
    for i <- 1..10 do
      {:ok, item} =
        Repo.insert(
          Item.changeset(%Item{}, %{
            title: "Jacket Item #{i}",
            price: "#{10 + i}.00",
            url: "http://e.com/jacket#{i}",
            source: "ebay"
          })
        )

      :ok = FTS5Index.upsert(item.id)
    end

    result = FTS5Index.search("jacket", 3)

    assert length(result) == 3,
           "expected exactly 3 results for top_n=3, got #{length(result)}: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-07 — search/2 with apostrophe in query returns matching item without crashing
  # ---------------------------------------------------------------------------

  test "I-07: search/2 with apostrophe in query returns matching item without crashing" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Mens Leather Jacket",
          price: "40.00",
          url: "http://e.com/6",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    result = "men's jacket" |> QueryProcessor.escape_fts_query() |> FTS5Index.search(5)

    assert Enum.any?(result, fn {id, score} ->
             id == item.id and score < 0
           end),
           "expected item_id #{item.id} with negative score, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-08 — search/2 with empty query string returns [] without crashing
  # ---------------------------------------------------------------------------

  test "I-08: search/2 with empty query string returns [] without crashing" do
    result = FTS5Index.search("", 10)

    assert result == [],
           "expected [] for empty query, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-09 — upsert/1 for an item with empty string title does not crash
  # ---------------------------------------------------------------------------

  test "I-09: upsert/1 for an item with empty string title does not crash" do
    # Bypass changeset validation — title is empty but must exist as a row in clothing_items
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Ecto.Adapters.SQL.query!(
      Repo,
      "INSERT INTO clothing_items (title, price, url, source, inserted_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
      ["", "5.00", "http://e.com/7", "ebay", now, now]
    )

    %{rows: [[item_id]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT id FROM clothing_items WHERE url = 'http://e.com/7' LIMIT 1",
        []
      )

    assert :ok = FTS5Index.upsert(item_id)

    result = FTS5Index.search("", 5)

    assert result == [],
           "expected [] for empty query after empty-title upsert, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-10 — FTS5 operator words in query do not cause a parse error
  # ---------------------------------------------------------------------------

  test "I-10: FTS5 operator words in query do not cause a parse error" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Leather Jacket",
          price: "35.00",
          url: "http://e.com/8",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    for query <- ["NOT jacket", "OR dress", "AND coat"] do
      result = FTS5Index.search(query, 5)

      assert is_list(result),
             "expected a list result for query #{inspect(query)}, got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # I-11 — search/2 by brand or description returns [] (only title is indexed)
  # ---------------------------------------------------------------------------

  test "I-11: search/2 by brand or description returns [] — only title is indexed" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Plain Shirt",
          brand: "Levi",
          description: "denim jacket style",
          price: "12.00",
          url: "http://e.com/9",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    brand_result = FTS5Index.search("levi", 5)
    desc_result = FTS5Index.search("denim jacket style", 5)

    refute Enum.any?(brand_result, fn {id, _} -> id == item.id end),
           "expected brand 'levi' NOT to match via FTS5 (not indexed), got: #{inspect(brand_result)}"

    refute Enum.any?(desc_result, fn {id, _} -> id == item.id end),
           "expected description NOT to match via FTS5 (not indexed), got: #{inspect(desc_result)}"
  end
end
