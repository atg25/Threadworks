defmodule ChatApp.AI.QueryUnderstander do
  @min_rrf_score 0.015
  @min_results 2

  @spec evaluate(list()) :: {:recommend, list()} | {:clarify, String.t()}
  def evaluate(items) do
    high_relevance = Enum.filter(items, &(&1.rrf_score >= @min_rrf_score))

    if length(high_relevance) >= @min_results do
      {:recommend, items}
    else
      {:clarify, "Could you tell me more about what you're looking for? For example, a style, occasion, or specific item type would help me find better matches."}
    end
  end
end
