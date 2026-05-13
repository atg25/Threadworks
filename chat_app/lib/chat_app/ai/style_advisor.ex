defmodule ChatApp.AI.StyleAdvisor do
  require Logger

  @moduledoc """
  Builds RAG-augmented prompts for the Threadworks style consultant.

  ## augment/2

  Searches for relevant clothing items and injects them into the base system
  prompt. The caller supplies token-budget context so `augment/2` can cap the
  number of injected items without touching the DB itself.

  ### Options

  - `conversation_tokens` (`non_neg_integer`, default: `0`) — total tokens
    consumed so far in the conversation.

  ### Item caps

  - `conversation_tokens <= 3000` → up to **10** items injected.
  - `conversation_tokens > 3000`  → up to **8** items injected.

  ### Return value

  Always returns `{:ok, prompt, items}`. HybridEngine errors are swallowed and
  logged; the base system prompt is returned with an empty items list.
  """

  @base_system_prompt """
  You are Threadworks AI, an executive-ready shopping and styling assistant for second-hand fashion.

  If asked how you work, explain that the app combines a polished streaming chat UI, RAG retrieval over a local clothing catalog, hybrid vector + keyword search, product recommendation cards, save/unsave actions, a saved-items page, user preferences for sizes/brands/budget/style keywords, background listing refresh workflows, and SQLite persistence for conversations, catalog data, saved items, and preferences.

  For styling requests, be concise, specific, and practical. Recommend only items supplied in AVAILABLE ITEMS.
  """

  @source_labels %{"ebay" => "eBay", "depop" => "Depop", "poshmark" => "Poshmark"}

  @json_instruction """

  After your response, output a JSON block:
  {"cards": [{"item_id": <N>, "reason": "<one sentence>"}]}
  Only include items you actually recommend.
  """

  @spec augment(String.t(), keyword()) ::
          {:ok, augmented_prompt :: String.t(), items :: list()}
  def augment(user_message, opts \\ []) do
    conversation_tokens = Keyword.get(opts, :conversation_tokens, 0)
    cap = if conversation_tokens > 3000, do: 8, else: 10
    engine = Application.get_env(:chat_app, :hybrid_engine_module, ChatApp.Search.HybridEngine)

    case engine.search(user_message) do
      {:ok, []} ->
        {:ok, @base_system_prompt, []}

      {:ok, results} ->
        capped = Enum.take(results, cap)
        prompt = build_prompt(@base_system_prompt, capped)
        {:ok, prompt, capped}

      {:error, reason} ->
        Logger.warning("StyleAdvisor: HybridEngine.search failed", reason: inspect(reason))
        {:ok, @base_system_prompt, []}
    end
  end

  @spec build_prompt(String.t(), list()) :: String.t()
  def build_prompt(base, items) do
    item_lines =
      items
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {item, n} ->
        condition = to_string(item.condition)
        source = Map.fetch!(@source_labels, to_string(item.source))
        price = item.price |> Decimal.round(2) |> Decimal.to_string()

        "[#{item.id || n}] #{item.title} | Size: #{item.size} | Condition: #{condition} | $#{price} | #{source}"
      end)

    base <>
      "\n\nAVAILABLE ITEMS:\n" <>
      item_lines <>
      @json_instruction
  end
end
