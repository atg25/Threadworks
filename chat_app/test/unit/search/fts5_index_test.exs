defmodule ChatApp.Search.FTS5IndexUnitTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias ChatApp.Search.QueryProcessor

  # ---------------------------------------------------------------------------
  # T-01 — escape_fts_query/1 strips single quotes
  # ---------------------------------------------------------------------------

  test "T-01: escape_fts_query/1 strips single quotes" do
    result = QueryProcessor.escape_fts_query("men's jacket")

    assert result == "mens jacket",
           "expected single quotes to be stripped entirely, got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-02 — escape_fts_query/1 makes hyphenated terms safe
  # ---------------------------------------------------------------------------

  test "T-02: escape_fts_query/1 makes hyphenated terms safe" do
    result = QueryProcessor.escape_fts_query("pre-owned")

    assert result == "preowned",
           "expected hyphen to be stripped (pre-owned → preowned), got: #{inspect(result)}"
  end

  # ---------------------------------------------------------------------------
  # T-03 — escape_fts_query/1 is a no-op for clean alphanumeric input
  # ---------------------------------------------------------------------------

  test "T-03: escape_fts_query/1 is a no-op for clean alphanumeric input" do
    input = "levi denim jacket"
    result = QueryProcessor.escape_fts_query(input)

    assert result == input,
           "expected no-op for clean alphanumeric input, but got: #{inspect(result)}"
  end
end
