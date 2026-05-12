defmodule ChatApp.Search.QueryProcessor do
  @size_terms ~w(xs s m l xl xxl small medium large)

  @stopwords ~w(
    a an the
    in on at to of for with by from
    is are was were be been being
    have has had do does did
    i me my we our you your he him his she her it its they them their
    this that these those which who what where when why how
    up down out about into over after
    as if so but than then there will would could should may might
    no yes all any some one two new just also only than
  ) -- @size_terms

  @fts5_operators ~w(and or not near)

  @synonyms %{
    "thrifted" => ["second-hand", "pre-owned", "vintage"],
    "preloved" => ["pre-owned", "second-hand"],
    "y2k" => ["2000s", "early 2000s"],
    "streetwear" => ["urban", "hypebeast"],
    "preppy" => ["ivy league", "nautical"]
  }

  @spec process(String.t()) :: String.t()
  def process(""), do: ""

  def process(query) do
    query
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&escape_fts_query/1)
    |> Enum.reject(&stopword?/1)
    |> Enum.map(&expand_synonyms/1)
    |> Enum.join(" ")
    |> String.trim()
  end

  @spec escape_fts_query(String.t()) :: String.t()
  def escape_fts_query(q) do
    q
    |> String.replace("'", "")
    |> String.replace(~r/(\w)-(\w)/, "\\1\\2")
    |> String.replace(~r/(?<!\w)-|-(?!\w)/, "")
  end

  defp stopword?(token), do: token in @stopwords

  defp expand_synonyms(token) do
    case Map.get(@synonyms, token) do
      nil -> wrap_operator(token)
      synonyms -> "(#{token} or #{Enum.join(synonyms, " or ")})"
    end
  end

  defp wrap_operator(token) when token in @fts5_operators, do: ~s("#{token}")
  defp wrap_operator(token), do: token
end
