defmodule ChatApp.SP0204FTS5IndexE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.Search.FTS5Index
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  # ---------------------------------------------------------------------------
  # E-01 — Positive: insert item, upsert FTS, search by title keyword — item appears first
  # ---------------------------------------------------------------------------

  test "E-01: insert three items, upsert all, search by title — levi jacket appears first" do
    {:ok, levi} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Vintage Levi Denim Jacket",
          price: "25.00",
          url: "http://e.com/e1a",
          source: "ebay"
        })
      )

    {:ok, nike} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Nike Running Shorts",
          price: "15.00",
          url: "http://e.com/e1b",
          source: "ebay"
        })
      )

    {:ok, silk} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Silk Evening Dress",
          price: "50.00",
          url: "http://e.com/e1c",
          source: "ebay"
        })
      )

    for item <- [levi, nike, silk] do
      :ok = FTS5Index.upsert(item.id)
    end

    result = FTS5Index.search("levi denim jacket", 3)

    assert length(result) >= 1,
           "expected at least one result, got: #{inspect(result)}"

    [{first_id, _first_score} | _] = result

    assert first_id == levi.id,
           "expected levi jacket (#{levi.id}) as first result, got: #{first_id}"

    Enum.each(result, fn {_id, score} ->
      assert score < 0,
             "expected all BM25 scores to be negative, got score: #{score}"
    end)

    if length(result) > 1 do
      scores = Enum.map(result, fn {_, s} -> s end)
      [s1 | _rest] = scores

      assert s1 == Enum.min(scores),
             "expected first result to have the most negative (min) score, got: #{inspect(scores)}"
    end
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: queries with only FTS5 metacharacters return [] without exception
  # ---------------------------------------------------------------------------

  test "E-02: queries with only FTS5 metacharacters return [] without exception" do
    for query <- ["", "()", "*"] do
      result = FTS5Index.search(query, 5)

      assert is_list(result),
             "expected a list for query #{inspect(query)}, got: #{inspect(result)}"

      assert result == [],
             "expected [] for metacharacter-only query #{inspect(query)}, got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # E-03 — Negative: orphaned FTS entry after item deletion — search does not crash
  # ---------------------------------------------------------------------------

  test "E-03: orphaned FTS entry after item deletion — search does not crash" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Orphaned Jacket",
          price: "18.00",
          url: "http://e.com/e3",
          source: "ebay"
        })
      )

    :ok = FTS5Index.upsert(item.id)

    Repo.delete!(item)

    result = FTS5Index.search("jacket", 5)

    assert is_list(result),
           "expected a list after orphaned FTS entry search, got: #{inspect(result)}"
  end
end
