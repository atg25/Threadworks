defmodule ChatApp.AI.StyleAdvisorTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  import Mox

  alias ChatApp.AI.StyleAdvisor
  alias ChatApp.Clothing.Item

  setup :verify_on_exit!

  defp item_fixture(overrides \\ %{}) do
    base = %Item{
      id: 1,
      title: "Levi's 501",
      size: "M",
      condition: "good",
      price: Decimal.new("45.00"),
      source: "ebay",
      url: "http://example.com/1",
      rrf_score: 0.05
    }

    Map.merge(base, overrides)
  end

  # ---------------------------------------------------------------------------
  # describe "build_prompt/2"
  # ---------------------------------------------------------------------------

  describe "build_prompt/2" do
    # U1 — AVAILABLE ITEMS header is present
    test "U1: AVAILABLE ITEMS header is present" do
      item = %Item{
        title: "Levi's 501",
        size: "28x30",
        condition: :good,
        price: Decimal.new("45.00"),
        source: :ebay
      }

      result = StyleAdvisor.build_prompt("base", [item])
      assert String.contains?(result, "AVAILABLE ITEMS:")
    end

    # U2 — Exactly N item lines with correct format
    test "U2: exactly N item lines with correct format" do
      items = [
        %Item{title: "Levi's 501",    size: "28x30", condition: :good,     price: Decimal.new("45.00"), source: :ebay},
        %Item{title: "CK Blazer",     size: "M",     condition: :like_new, price: Decimal.new("78.00"), source: :depop},
        %Item{title: "Floral Blouse", size: "S",     condition: :fair,     price: Decimal.new("22.00"), source: :poshmark}
      ]

      result = StyleAdvisor.build_prompt("base", items)
      lines = String.split(result, "\n")
      item_lines = Enum.filter(lines, &Regex.match?(~r/^\[\d+\]/, &1))
      assert length(item_lines) == 3
    end

    # U3 — Base prompt appears before AVAILABLE ITEMS block
    test "U3: base prompt appears before AVAILABLE ITEMS block" do
      base = "You are a style advisor."
      item = %Item{
        title: "Jeans",
        size: "M",
        condition: :good,
        price: Decimal.new("30.00"),
        source: :ebay
      }

      result = StyleAdvisor.build_prompt(base, [item])
      base_pos  = :binary.match(result, base) |> elem(0)
      items_pos = :binary.match(result, "AVAILABLE ITEMS:") |> elem(0)
      assert base_pos < items_pos
    end

    # U4 — Item numbering is 1-based and sequential
    test "U4: item numbering is 1-based and sequential" do
      items =
        for _ <- 1..3,
            do: %Item{title: "X", size: "M", condition: :good, price: Decimal.new("10.00"), source: :ebay}

      result = StyleAdvisor.build_prompt("base", items)
      assert String.contains?(result, "[1]")
      assert String.contains?(result, "[2]")
      assert String.contains?(result, "[3]")
      refute String.contains?(result, "[0]")
      refute String.contains?(result, "[4]")
    end

    # U5 — Empty items list does not crash; produces zero item lines
    test "U5: empty items list does not crash; produces zero item lines" do
      result = StyleAdvisor.build_prompt("base", [])
      assert String.contains?(result, "AVAILABLE ITEMS:")
      lines = String.split(result, "\n")
      item_lines = Enum.filter(lines, &Regex.match?(~r/^\[\d+\]/, &1))
      assert item_lines == []
    end

    # U6 — JSON instruction block present with exact spec wording
    test "U6: JSON instruction block present with exact spec wording" do
      item = %Item{
        title: "Jeans",
        size: "M",
        condition: :good,
        price: Decimal.new("30.00"),
        source: :ebay
      }

      result = StyleAdvisor.build_prompt("base", [item])
      assert String.contains?(result, "After your response, output a JSON block:")
      assert String.contains?(result, ~s({"cards": [{"item_id":))
      assert String.contains?(result, "Only include items you actually recommend.")
    end

    # M1 — Full item line contains all five fields in correct order
    test "M1: full item line contains all five fields in correct order" do
      item = %Item{
        title: "Levi's 501 Jeans",
        size: "28x30",
        condition: :good,
        price: Decimal.new("45.00"),
        source: :ebay
      }

      result = StyleAdvisor.build_prompt("base", [item])

      assert Regex.match?(
               ~r/\[1\] Levi's 501 Jeans \| Size: 28x30 \| Condition: good \| \$45\.00 \| eBay/,
               result
             )
    end
  end

  # ---------------------------------------------------------------------------
  # describe "augment/2"
  # ---------------------------------------------------------------------------

  describe "augment/2" do
    # M2 — Default 10-item cap applied when no budget pressure
    test "M2: default 10-item cap applied when no budget pressure" do
      stub(ChatApp.Search.MockHybridEngine, :search, fn _ ->
        items = for i <- 1..12, do: item_fixture(%{id: i})
        {:ok, items}
      end)

      {:ok, _prompt, items} = StyleAdvisor.augment("query")
      assert length(items) == 10
    end
  end
end
