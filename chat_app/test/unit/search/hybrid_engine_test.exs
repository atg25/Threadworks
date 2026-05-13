defmodule ChatApp.Search.HybridEngineUnitTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias ChatApp.Search.HybridEngine

  # ---------------------------------------------------------------------------
  # T-01 — rrf_fuse/2: item in both pipelines gets sum of both terms
  # ---------------------------------------------------------------------------

  test "T-01: item appearing in both pipelines gets sum of both terms" do
    # vec_ranks: item 1 rank 1, item 2 rank 2
    # fts_ranks: item 2 rank 1, item 3 rank 2
    vec_ranks = %{1 => 1, 2 => 2}
    fts_ranks = %{2 => 1, 3 => 2}

    result = HybridEngine.rrf_fuse(vec_ranks, fts_ranks)

    scores = Map.new(result)

    item1_score = 1.0 / (60 + 1)
    item2_score = 1.0 / (60 + 2) + 1.0 / (60 + 1)
    item3_score = 1.0 / (60 + 2)

    assert_in_delta scores[1], item1_score, 1.0e-10,
                    "item 1 score mismatch: got #{scores[1]}, expected #{item1_score}"

    assert_in_delta scores[2], item2_score, 1.0e-10,
                    "item 2 score mismatch: got #{scores[2]}, expected #{item2_score}"

    assert_in_delta scores[3], item3_score, 1.0e-10,
                    "item 3 score mismatch: got #{scores[3]}, expected #{item3_score}"

    # item 2 has highest score — must be first
    [{first_id, _} | _] = result

    assert first_id == 2,
           "expected item 2 first (highest combined score), got #{first_id}"
  end

  # ---------------------------------------------------------------------------
  # T-02 — rrf_fuse/2: item in only one pipeline gets a single term
  # ---------------------------------------------------------------------------

  test "T-02: item in only one pipeline gets a single term" do
    vec_ranks = %{5 => 3}
    fts_ranks = %{}

    result = HybridEngine.rrf_fuse(vec_ranks, fts_ranks)

    scores = Map.new(result)

    expected_score = 1.0 / (60 + 3)

    assert Map.has_key?(scores, 5),
           "expected item 5 in result, got: #{inspect(result)}"

    assert_in_delta scores[5], expected_score, 1.0e-10,
                    "item 5 score mismatch: got #{scores[5]}, expected #{expected_score}"
  end

  # ---------------------------------------------------------------------------
  # T-03 — rrf_fuse/2: rank-1 item in both pipelines equals 2/61
  # ---------------------------------------------------------------------------

  test "T-03: rank-1 item in both pipelines equals 2/61" do
    vec_ranks = %{7 => 1}
    fts_ranks = %{7 => 1}

    result = HybridEngine.rrf_fuse(vec_ranks, fts_ranks)

    scores = Map.new(result)

    expected_score = 2.0 / 61

    assert Map.has_key?(scores, 7),
           "expected item 7 in result, got: #{inspect(result)}"

    assert_in_delta scores[7], expected_score, 1.0e-10,
                    "item 7 score: got #{scores[7]}, expected #{expected_score} (2/61)"
  end

  # ---------------------------------------------------------------------------
  # T-04 — rrf_fuse/2 output is sorted DESC by score
  # ---------------------------------------------------------------------------

  test "T-04: output is sorted DESC by score" do
    vec_ranks = %{1 => 1, 2 => 2, 3 => 3}
    fts_ranks = %{3 => 1, 2 => 2, 1 => 3}

    result = HybridEngine.rrf_fuse(vec_ranks, fts_ranks)

    scores = Enum.map(result, fn {_, score} -> score end)

    sorted_desc = Enum.sort(scores, :desc)

    assert scores == sorted_desc,
           "expected scores sorted DESC, got: #{inspect(scores)}"
  end

  # ---------------------------------------------------------------------------
  # T-05 — All rrf_score values are positive floats <= 2/61
  # ---------------------------------------------------------------------------

  test "T-05: all rrf_score values are positive floats <= 2/61" do
    vec_ranks = %{1 => 1, 2 => 2, 3 => 3}
    fts_ranks = %{1 => 2, 2 => 1, 3 => 3}

    result = HybridEngine.rrf_fuse(vec_ranks, fts_ranks)

    assert length(result) >= 1,
           "expected at least one result, got: #{inspect(result)}"

    Enum.each(result, fn {id, score} ->
      assert is_float(score),
             "expected float score for item #{id}, got: #{inspect(score)}"

      assert score > 0,
             "expected positive score for item #{id}, got: #{score}"

      assert score <= 2.0 / 61,
             "expected score <= 2/61 for item #{id}, got: #{score}"
    end)
  end
end
