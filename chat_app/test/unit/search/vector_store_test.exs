defmodule ChatApp.Search.VectorStoreUnitTest do
  use ChatApp.DataCase, async: false

  @moduletag :unit

  alias ChatApp.Search.VectorStore

  @embeddings Code.eval_file(Path.join([__DIR__, "../../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a
  @fixture_b @embeddings.fixture_b

  # ---------------------------------------------------------------------------
  # T-01 — upsert/2 returns :ok for a valid item_id and 512-dim vector
  # ---------------------------------------------------------------------------

  test "T-01: upsert/2 returns :ok for a valid item_id and 512-dim vector" do
    assert :ok = VectorStore.upsert(99, @fixture_a)
  end

  # ---------------------------------------------------------------------------
  # T-02 — upsert/2 raises ArgumentError for a vector shorter than 512 elements
  # ---------------------------------------------------------------------------

  test "T-02: upsert/2 raises ArgumentError for a vector shorter than 512 elements" do
    assert_raise ArgumentError, fn ->
      VectorStore.upsert(1, List.duplicate(1.0, 100))
    end
  end

  # ---------------------------------------------------------------------------
  # T-03 — upsert/2 raises ArgumentError for a vector longer than 512 elements
  # ---------------------------------------------------------------------------

  test "T-03: upsert/2 raises ArgumentError for a vector longer than 512 elements" do
    assert_raise ArgumentError, fn ->
      VectorStore.upsert(1, List.duplicate(1.0, 600))
    end
  end

  # ---------------------------------------------------------------------------
  # T-04 — upsert/2 raises FunctionClauseError when vector contains string elements
  # ---------------------------------------------------------------------------

  test "T-04: upsert/2 raises FunctionClauseError when vector contains string elements" do
    assert_raise FunctionClauseError, fn ->
      VectorStore.upsert(1, List.duplicate("x", 512))
    end
  end

  # ---------------------------------------------------------------------------
  # T-05 — search/2 returns an empty list when the table is empty
  # ---------------------------------------------------------------------------

  test "T-05: search/2 returns an empty list when the table is empty" do
    assert [] = VectorStore.search(@fixture_a, 5)
  end

  # ---------------------------------------------------------------------------
  # T-06 — search/2 returns at most top_n results
  # ---------------------------------------------------------------------------

  test "T-06: search/2 returns at most top_n results" do
    fixtures = [@fixture_a, @fixture_b]

    for i <- 1..10 do
      vec = Enum.at(fixtures, rem(i - 1, 2))
      :ok = VectorStore.upsert(i, vec)
    end

    result = VectorStore.search(@fixture_a, 3)
    assert length(result) <= 3
  end

  # ---------------------------------------------------------------------------
  # T-07 — search/2 result elements are {integer(), float()} tuples
  # ---------------------------------------------------------------------------

  test "T-07: search/2 result elements are {integer(), float()} tuples" do
    :ok = VectorStore.upsert(42, @fixture_a)

    result = VectorStore.search(@fixture_a, 5)

    assert length(result) > 0

    Enum.each(result, fn {item_id, distance} ->
      assert is_integer(item_id),
             "expected integer item_id, got #{inspect(item_id)}"

      assert is_float(distance),
             "expected float distance, got #{inspect(distance)}"
    end)
  end
end
