defmodule ChatApp.AI.QueryUnderstanderTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias ChatApp.AI.QueryUnderstander
  alias ChatApp.Clothing.Item

  # ---------------------------------------------------------------------------
  # describe "evaluate/1"
  # ---------------------------------------------------------------------------

  describe "evaluate/1" do
    # U7 — Returns :clarify for empty list
    test "U7: returns :clarify for empty list" do
      assert {:clarify, msg} = QueryUnderstander.evaluate([])
      assert is_binary(msg) and msg != ""
    end

    # U8 — Returns :clarify when all items below threshold
    test "U8: returns :clarify when all items below threshold (0.008, 0.010 < 0.015)" do
      items = [
        %Item{rrf_score: 0.008},
        %Item{rrf_score: 0.010}
      ]

      assert {:clarify, _} = QueryUnderstander.evaluate(items)
    end

    # U9 — Returns :clarify when exactly one item meets threshold
    test "U9: returns :clarify when exactly one item meets threshold" do
      items = [%Item{rrf_score: 0.02}, %Item{rrf_score: 0.008}]
      assert {:clarify, _} = QueryUnderstander.evaluate(items)
    end

    # U10 — Returns :recommend when exactly two items meet threshold
    test "U10: returns :recommend when exactly two items meet threshold" do
      items = [%Item{rrf_score: 0.02}, %Item{rrf_score: 0.02}]
      assert {:recommend, ^items} = QueryUnderstander.evaluate(items)
    end

    # U11 — Returns :recommend at exact threshold boundary (0.015)
    test "U11: returns :recommend at exact threshold boundary (0.015)" do
      items = [%Item{rrf_score: 0.015}, %Item{rrf_score: 0.015}]
      assert {:recommend, _} = QueryUnderstander.evaluate(items)
    end

    # U12 — :recommend returns the full input list, not the filtered high-relevance subset
    test "U12: :recommend returns the full input list, not filtered high-relevance subset" do
      items = [
        %Item{rrf_score: 0.02},
        %Item{rrf_score: 0.02},
        %Item{rrf_score: 0.001}
      ]

      assert {:recommend, returned} = QueryUnderstander.evaluate(items)
      assert length(returned) == 3
      assert Enum.any?(returned, &(&1.rrf_score == 0.001))
    end

    # M2 — :recommend fires with exactly 2 qualifying items among a 10-item list
    test "M2: :recommend fires with exactly 2 qualifying items among a 10-item list" do
      high = [%Item{rrf_score: 0.02}, %Item{rrf_score: 0.016}]
      low = List.duplicate(%Item{rrf_score: 0.005}, 8)
      items = high ++ low

      assert {:recommend, returned} = QueryUnderstander.evaluate(items)
      assert length(returned) == 10
    end
  end
end
