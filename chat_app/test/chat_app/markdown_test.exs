defmodule ChatApp.MarkdownTest do
  use ExUnit.Case, async: true

  alias ChatApp.Markdown

  # Positive: plain text passes through unchanged (wrapped in <p>)
  test "plain text is wrapped in a paragraph tag" do
    result = Markdown.to_html("Hello world")
    assert result =~ "<p>"
    assert result =~ "Hello world"
  end

  # Positive: bold syntax renders as <strong>
  test "**bold** renders as <strong>" do
    result = Markdown.to_html("**bold text**")
    assert result =~ "<strong>bold text</strong>"
  end

  # Positive: italic syntax renders as <em>
  test "_italic_ renders as <em>" do
    result = Markdown.to_html("_italic text_")
    assert result =~ "<em>italic text</em>"
  end

  # Positive: inline code renders as <code>
  test "`code` renders as <code>" do
    result = Markdown.to_html("`inline_code`")
    assert result =~ "<code"
    assert result =~ "inline_code"
  end

  # Positive: fenced code block renders as <pre><code>
  test "fenced code block renders as <pre><code>" do
    md = "```\nsome code\n```"
    result = Markdown.to_html(md)
    assert result =~ "<pre"
    assert result =~ "<code"
    assert result =~ "some code"
  end

  # Positive: unordered list renders as <ul><li>
  test "unordered list renders as <ul><li>" do
    result = Markdown.to_html("- item one\n- item two")
    assert result =~ "<ul>"
    assert result =~ "<li>"
    assert result =~ "item one"
  end

  # Positive: heading renders as <h2>
  test "## heading renders as <h2>" do
    result = Markdown.to_html("## My Heading")
    assert result =~ "<h2>"
    assert result =~ "My Heading"
  end

  # Positive: returns a binary string
  test "to_html/1 always returns a binary" do
    result = Markdown.to_html("anything")
    assert is_binary(result)
  end

  # Negative: empty string returns empty or whitespace string (no crash)
  test "empty string does not crash" do
    result = Markdown.to_html("")
    assert is_binary(result)
  end

  test "raw HTML in input is HTML-escaped, not passed through" do
    result = Markdown.to_html("<script>alert('xss')</script>")
    refute result =~ "<script>"
    assert result =~ "&lt;script&gt;"
  end

  test "fenced code blocks still render as <pre><code>" do
    result = Markdown.to_html("```\nlet x = 1\n```")
    assert result =~ "<pre><code"
    assert result =~ "let x = 1"
  end

  # Negative: nil input raises FunctionClauseError (guard: when is_binary(text))
  test "nil input raises FunctionClauseError" do
    assert_raise FunctionClauseError, fn -> Markdown.to_html(nil) end
  end

  # ---------------------------------------------------------------------------
  # TASK 4 — Code-block wrapping tests
  # ---------------------------------------------------------------------------

  test "to_html wraps a fenced elixir block in .ui-code-block with data-language=elixir" do
    md = "```elixir\nIO.puts(\"hi\")\n```"
    result = Markdown.to_html(md)

    assert result =~ ~s(class="ui-code-block")
    assert result =~ ~s(data-language="elixir")
    # Header span should mention "elixir"
    assert result =~ "elixir"
    # The pre/code block should still be present
    assert result =~ "<pre>"
    assert result =~ "<code"
  end

  test "to_html with an unlabeled fence sets data-language=text" do
    md = "```\nplain\n```"
    result = Markdown.to_html(md)

    assert result =~ ~s(data-language="text")
  end

  test "to_html does NOT wrap inline code (single backtick)" do
    md = "`print(\"hi\")`"
    result = Markdown.to_html(md)

    assert result =~ "<code"
    refute result =~ ~s(class="ui-code-block")
  end

  test "to_html with multiple code blocks wraps each independently" do
    md = "```elixir\nfoo\n```\n\n```python\nbar\n```"
    result = Markdown.to_html(md)

    count =
      result
      |> String.split(~s(class="ui-code-block"))
      |> length()
      |> Kernel.-(1)

    assert count == 2
    assert result =~ ~s(data-language="elixir")
    assert result =~ ~s(data-language="python")
  end

  test "XSS protection is preserved through the code-block wrapper" do
    md = "```\n<script>alert(1)</script>\n```"
    result = Markdown.to_html(md)

    refute result =~ "<script>"
    assert result =~ "&lt;script&gt;"
    assert result =~ ~s(class="ui-code-block")
  end
end
