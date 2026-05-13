defmodule ChatApp.AI.StyleAdvisorIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

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
  # I1 — augment/2 passes the user message verbatim to HybridEngine.search
  # ---------------------------------------------------------------------------

  test "I1: augment/2 passes the user message verbatim to HybridEngine.search" do
    expect(ChatApp.Search.MockHybridEngine, :search, fn "blue jeans" ->
      {:ok, [item_fixture()]}
    end)

    {:ok, _prompt, _items} = StyleAdvisor.augment("blue jeans")
  end

  # ---------------------------------------------------------------------------
  # I2 — augment/2 calls build_prompt when results are non-empty
  # ---------------------------------------------------------------------------

  test "I2: augment/2 calls build_prompt when results are non-empty" do
    items = [item_fixture()]
    expect(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:ok, items} end)
    {:ok, prompt, returned_items} = StyleAdvisor.augment("blue jeans")
    assert String.contains?(prompt, "AVAILABLE ITEMS:")
    assert String.contains?(prompt, "[1]")
    assert returned_items == items
  end

  # ---------------------------------------------------------------------------
  # I3 — augment/2 returns base prompt when search is empty
  # ---------------------------------------------------------------------------

  test "I3: augment/2 returns base prompt when search is empty" do
    expect(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:ok, []} end)
    {:ok, prompt, items} = StyleAdvisor.augment("anything")
    assert items == []
    refute String.contains?(prompt, "AVAILABLE ITEMS:")
    assert String.starts_with?(prompt, "You are Threadworks AI")
  end

  # ---------------------------------------------------------------------------
  # I4 — Token budget: 10 items capped to 8 when conversation_tokens > 3000
  # ---------------------------------------------------------------------------

  test "I4: token budget caps to 8 items when conversation_tokens > 3000" do
    fifteen_items = for i <- 1..15, do: item_fixture(%{id: i, rrf_score: 0.02})
    expect(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:ok, fifteen_items} end)
    {:ok, _prompt, items} = StyleAdvisor.augment("summer dress", conversation_tokens: 3001)
    assert length(items) == 8
  end

  # ---------------------------------------------------------------------------
  # I5 — Token budget: 10 items NOT capped when conversation_tokens <= 3000
  # ---------------------------------------------------------------------------

  test "I5: token budget does NOT cap when conversation_tokens <= 3000" do
    fifteen_items = for i <- 1..15, do: item_fixture(%{id: i, rrf_score: 0.02})
    expect(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:ok, fifteen_items} end)
    {:ok, _prompt, items} = StyleAdvisor.augment("summer dress", conversation_tokens: 3000)
    assert length(items) == 10
  end

  # ---------------------------------------------------------------------------
  # M1 — HybridEngine error returns {:ok, base_prompt, []} without crashing
  # ---------------------------------------------------------------------------

  test "M1: HybridEngine error returns {:ok, base_prompt, []} without crashing" do
    expect(ChatApp.Search.MockHybridEngine, :search, fn _ -> {:error, :timeout} end)
    {:ok, prompt, items} = StyleAdvisor.augment("query")
    assert items == []
    refute String.contains?(prompt, "AVAILABLE ITEMS:")
  end
end
