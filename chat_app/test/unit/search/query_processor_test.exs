defmodule ChatApp.Search.QueryProcessorTest do
  use ExUnit.Case, async: true

  alias ChatApp.Search.QueryProcessor

  # ---------------------------------------------------------------------------
  # T-01 — process/1 lowercases the query
  # ---------------------------------------------------------------------------

  test "T-01: process/1 lowercases the query" do
    result = QueryProcessor.process("Vintage LEVI Denim")

    refute result =~ ~r/[A-Z]/,
           "expected all lowercase output, but got uppercase characters: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-02 — process/1 removes common English stopwords
  # ---------------------------------------------------------------------------

  test "T-02: process/1 removes common English stopwords" do
    result = QueryProcessor.process("the a vintage jacket")

    tokens = String.split(result, ~r/\s+/, trim: true)

    refute "the" in tokens,
           "expected stopword \"the\" to be removed, but it appears in: #{inspect(result)}"

    refute "a" in tokens,
           "expected stopword \"a\" to be removed, but it appears in: #{inspect(result)}"

    assert result =~ "vintage",
           "expected \"vintage\" to be preserved, but got: #{inspect(result)}"

    assert result =~ "jacket",
           "expected \"jacket\" to be preserved, but got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-03 — process/1 preserves all nine clothing size terms
  # ---------------------------------------------------------------------------

  test "T-03: process/1 preserves all nine clothing size terms" do
    result = QueryProcessor.process("xs s m l xl xxl small medium large jacket")

    for size <- ~w(xs s m l xl xxl small medium large) do
      assert result =~ ~r/\b#{size}\b/,
             "expected clothing size \"#{size}\" to be preserved, but got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-04 — process/1 expands "thrifted" additively — original term and all three synonyms
  # ---------------------------------------------------------------------------

  test "T-04: process/1 expands \"thrifted\" additively — original term and all three synonyms present" do
    result = QueryProcessor.process("thrifted jacket")

    for term <- ["thrifted", "second-hand", "pre-owned", "vintage"] do
      assert result =~ term,
             "expected \"#{term}\" in output, but got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-05 — process/1 expansion uses OR grouping syntax
  # ---------------------------------------------------------------------------

  test "T-05: process/1 expansion uses OR grouping syntax" do
    result = QueryProcessor.process("thrifted jacket")

    assert result =~ "(thrifted or second-hand or pre-owned or vintage)",
           "expected OR group \"(thrifted or second-hand or pre-owned or vintage)\" in output, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-06 — process/1 expands "preloved"
  # ---------------------------------------------------------------------------

  test "T-06: process/1 expands \"preloved\"" do
    result = QueryProcessor.process("preloved coat")

    for term <- ["preloved", "pre-owned", "second-hand"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"preloved\", but got: #{inspect(result)}"
    end

    assert result =~ ~r/\(preloved or .+ or .+\)/ or result =~ ~r/\(.+or preloved or .+\)/ or result =~ ~r/\(.+or .+ or preloved\)/,
           "expected preloved and synonyms in a single OR group, but got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-07 — process/1 expands "y2k"
  # ---------------------------------------------------------------------------

  test "T-07: process/1 expands \"y2k\"" do
    result = QueryProcessor.process("y2k top")

    for term <- ["y2k", "2000s"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"y2k\", but got: #{inspect(result)}"
    end

    assert result =~ "early 2000s",
           "expected \"early 2000s\" in OR group for \"y2k\", but got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-08 — process/1 expands "streetwear"
  # ---------------------------------------------------------------------------

  test "T-08: process/1 expands \"streetwear\"" do
    result = QueryProcessor.process("streetwear pants")

    for term <- ["streetwear", "urban", "hypebeast"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"streetwear\", but got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-09 — process/1 expands "preppy"
  # ---------------------------------------------------------------------------

  test "T-09: process/1 expands \"preppy\"" do
    result = QueryProcessor.process("preppy blazer")

    for term <- ["preppy", "ivy league", "nautical"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"preppy\", but got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-10 — process/1 passes unknown terms through unchanged
  # ---------------------------------------------------------------------------

  test "T-10: process/1 passes unknown terms through unchanged" do
    result = QueryProcessor.process("zardigan mesh corset")

    for term <- ["zardigan", "mesh", "corset"] do
      assert result =~ term,
             "expected unknown term \"#{term}\" to be preserved (lowercased), but got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-11 — process/1 handles empty string
  # ---------------------------------------------------------------------------

  test "T-11: process/1 handles empty string" do
    assert QueryProcessor.process("") == "",
           "expected empty string to return empty string"
  end

  # ---------------------------------------------------------------------------
  # T-12 — process/1 normalizes whitespace
  # ---------------------------------------------------------------------------

  test "T-12: process/1 normalizes whitespace" do
    result = QueryProcessor.process("  vintage   jacket  ")

    refute result =~ ~r/^\s/,
           "expected no leading whitespace, got: #{inspect(result)}"

    refute result =~ ~r/\s$/,
           "expected no trailing whitespace, got: #{inspect(result)}"

    refute result =~ ~r/\s{2,}/,
           "expected no consecutive spaces, got: #{inspect(result)}"

    assert result =~ "vintage",
           "expected \"vintage\" in output after normalization"

    assert result =~ "jacket",
           "expected \"jacket\" in output after normalization"
  end

  # ---------------------------------------------------------------------------
  # T-13 — process/1 wraps FTS5 operator tokens in double-quotes
  # ---------------------------------------------------------------------------

  test "T-13: process/1 wraps FTS5 operator tokens in double-quotes" do
    for {input, expected_token} <- [
      {"NOT jacket", ~s("not")},
      {"OR dress", ~s("or")},
      {"AND coat", ~s("and")},
      {"NEAR boots", ~s("near")}
    ] do
      result = QueryProcessor.process(input)

      assert result =~ expected_token,
             "expected #{inspect(expected_token)} in output for input #{inspect(input)}, got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # T-14 — escape_fts_query/1 doubles single quotes
  # ---------------------------------------------------------------------------

  test "T-14: escape_fts_query/1 strips single quotes" do
    result = QueryProcessor.escape_fts_query("men's jacket")

    assert result == "mens jacket",
           "expected single quotes to be stripped, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-15 — escape_fts_query/1 makes hyphenated terms safe
  # ---------------------------------------------------------------------------

  test "T-15: escape_fts_query/1 makes hyphenated terms safe" do
    result = QueryProcessor.escape_fts_query("pre-owned")

    refute result =~ ~r/\w-\w/,
           "expected bare hyphen between word characters to be escaped, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-16 — escape_fts_query/1 is a no-op for clean alphanumeric queries
  # ---------------------------------------------------------------------------

  test "T-16: escape_fts_query/1 is a no-op for clean alphanumeric queries" do
    input = "levi denim jacket"
    result = QueryProcessor.escape_fts_query(input)

    assert result == input,
           "expected no-op for clean alphanumeric input, but got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # E-01 — Positive: full pipeline on a realistic multi-term query
  # ---------------------------------------------------------------------------

  test "E-01: full pipeline on a realistic multi-term query" do
    result = QueryProcessor.process("Thrifted Y2K Streetwear L Jacket")

    refute result =~ ~r/[A-Z]/,
           "expected all lowercase output, got uppercase characters: #{inspect(result)}"

    assert result =~ ~r/\bl\b/,
           "expected size term \"l\" preserved (not stripped as stopword), got: #{inspect(result)}"

    assert result =~ "jacket",
           "expected \"jacket\" in output, got: #{inspect(result)}"

    for term <- ["thrifted", "second-hand", "pre-owned", "vintage"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"thrifted\", got: #{inspect(result)}"
    end

    for term <- ["y2k", "2000s", "early 2000s"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"y2k\", got: #{inspect(result)}"
    end

    for term <- ["streetwear", "urban", "hypebeast"] do
      assert result =~ term,
             "expected \"#{term}\" in OR group for \"streetwear\", got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # E-02 — Negative: query composed entirely of stopwords returns empty string
  # ---------------------------------------------------------------------------

  test "E-02: query composed entirely of stopwords returns empty string" do
    result = QueryProcessor.process("the a an in of")

    assert result == "",
           "expected empty string for all-stopword query, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # E-03 — Negative: query with apostrophes and hyphens produces no unescaped single quotes
  # ---------------------------------------------------------------------------

  test "E-03: query with apostrophes and hyphens produces no unescaped single quotes" do
    result = QueryProcessor.process("men's pre-owned y2k jacket")

    refute String.contains?(result, "'"),
           "expected no bare single quotes in output (FTS5 safety), got: #{inspect(result)}"
  end
end
