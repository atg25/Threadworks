defmodule ChatApp.Search.VectorStoreIntegrationTest do
  use ChatApp.DataCase, async: false

  @moduletag :integration

  alias ChatApp.Search.VectorStore
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  @embeddings Code.eval_file(Path.join([__DIR__, "../../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a
  @fixture_b @embeddings.fixture_b

  # ---------------------------------------------------------------------------
  # I-01 — upsert/2 → search/2 round-trip: self-distance is less than 0.001
  # ---------------------------------------------------------------------------

  test "I-01: round-trip self-distance is less than 0.001" do
    :ok = VectorStore.upsert(99, @fixture_a)

    result = VectorStore.search(@fixture_a, 5)

    assert [{99, distance} | _] = result,
           "expected item_id 99 as first result, got #{inspect(result)}"

    assert distance < 0.001,
           "expected self-distance < 0.001, got #{distance}"
  end

  # ---------------------------------------------------------------------------
  # I-02 — search/2 ranks closer vector before distant vector
  # ---------------------------------------------------------------------------

  test "I-02: search/2 ranks closer vector before distant vector" do
    :ok = VectorStore.upsert(1, @fixture_a)
    :ok = VectorStore.upsert(2, @fixture_b)

    [{first_id, _} | [{second_id, _} | _]] = VectorStore.search(@fixture_a, 2)

    assert first_id == 1,
           "expected item_id 1 (fixture_a) first, got #{first_id}"

    assert second_id == 2,
           "expected item_id 2 (fixture_b) second, got #{second_id}"
  end

  # ---------------------------------------------------------------------------
  # I-03 — upsert/2 is idempotent — calling it three times does not create duplicates
  # ---------------------------------------------------------------------------

  test "I-03: upsert/2 is idempotent — no duplicate rows after three calls" do
    :ok = VectorStore.upsert(99, @fixture_a)
    :ok = VectorStore.upsert(99, @fixture_a)
    :ok = VectorStore.upsert(99, @fixture_a)

    result = VectorStore.search(@fixture_a, 10)

    count = Enum.count(result, fn {id, _} -> id == 99 end)

    assert count == 1,
           "expected exactly 1 entry for item_id 99, got #{count}: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-04 — upsert/2 second call with different vector replaces first
  # ---------------------------------------------------------------------------

  test "I-04: second upsert with different vector replaces the first" do
    :ok = VectorStore.upsert(99, @fixture_a)
    :ok = VectorStore.upsert(99, @fixture_b)

    [{result_id, distance}] = VectorStore.search(@fixture_b, 1)

    assert result_id == 99,
           "expected item_id 99, got #{result_id}"

    assert distance < 0.001,
           "expected self-distance < 0.001 for fixture_b, got #{distance}"
  end

  # ---------------------------------------------------------------------------
  # I-05 — search/2 result rowid equals the item_id passed to upsert/2
  # ---------------------------------------------------------------------------

  test "I-05: returned item_id equals the id passed to upsert/2, not an autoincrement" do
    :ok = VectorStore.upsert(42, @fixture_a)

    result = VectorStore.search(@fixture_a, 5)

    assert Enum.any?(result, fn {id, _} -> id == 42 end),
           "expected item_id 42 in results, got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # I-06 — search/2 returns item_id even after the clothing_items row is deleted
  # ---------------------------------------------------------------------------

  test "I-06: VectorStore has no FK awareness — orphan vector remains searchable after row deletion" do
    {:ok, item} =
      Repo.insert(
        Item.changeset(%Item{}, %{
          title: "Test Jacket",
          price: "29.99",
          url: "https://example.com/jacket",
          source: "test"
        })
      )

    :ok = VectorStore.upsert(item.id, @fixture_a)

    Repo.delete!(item)

    result = VectorStore.search(@fixture_a, 5)

    assert Enum.any?(result, fn {id, _} -> id == item.id end),
           "expected orphaned item_id #{item.id} still in results after deletion, got #{inspect(result)}"
  end
end
