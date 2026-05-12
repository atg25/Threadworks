defmodule ChatApp.SP0203VectorStoreE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  alias ChatApp.Search.VectorStore

  @embeddings Code.eval_file(Path.join([__DIR__, "../fixtures/embeddings.exs"])) |> elem(0)
  @fixture_a @embeddings.fixture_a
  @fixture_b @embeddings.fixture_b
  @fixture_c @embeddings.fixture_c

  # ---------------------------------------------------------------------------
  # E-01 — Positive: upsert three fixtures, search with fixture_a returns fixture_a item first
  # ---------------------------------------------------------------------------

  test "E-01: upsert three fixtures — search with fixture_a returns fixture_a item first with self-distance < 0.001" do
    :ok = VectorStore.upsert(1, @fixture_a)
    :ok = VectorStore.upsert(2, @fixture_b)
    :ok = VectorStore.upsert(3, @fixture_c)

    result = VectorStore.search(@fixture_a, 3)

    assert length(result) == 3,
           "expected 3 results, got #{length(result)}: #{inspect(result)}"

    [{first_id, first_distance} | _rest] = result

    assert first_id == 1,
           "expected item_id 1 (fixture_a) first, got #{first_id}"

    assert first_distance < 0.001,
           "expected self-distance < 0.001, got #{first_distance}"
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: search on empty table returns [] without crashing
  # ---------------------------------------------------------------------------

  test "E-02: search on empty table returns [] without crashing" do
    result = VectorStore.search(@fixture_a, 10)

    assert result == [],
           "expected [], got #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # E-03 — Negative: upsert with string-element vector raises before reaching DB
  # ---------------------------------------------------------------------------

  test "E-03: upsert with string-element vector raises FunctionClauseError before reaching DB" do
    assert_raise FunctionClauseError, fn ->
      VectorStore.upsert(1, List.duplicate("bad", 512))
    end
  end
end
