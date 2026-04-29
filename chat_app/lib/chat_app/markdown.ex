defmodule ChatApp.Markdown do
  @moduledoc """
  Converts Markdown to HTML, HTML-escaping any embedded raw HTML.
  Safe to render with Phoenix.HTML.raw/1 in HEEx templates because input is
  HTML-escaped before Markdown parsing while still emitting <code>/<pre> for
  fenced code blocks.
  """

  @doc """
  Converts a Markdown string to an HTML string.
  Returns a plain binary — callers must wrap in `Phoenix.HTML.raw/1` before
  inserting into HEEx templates.
  """
  def to_html(text) when is_binary(text) do
    escaped_text =
      text
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    {:ok, html, _warnings} =
      Earmark.as_html(escaped_text,
        escape: false,
        smartypants: false
      )

    html
    |> wrap_fenced_code_blocks()
    |> String.replace(~s(<code class="inline">), "<code>")
  end

  defp wrap_fenced_code_blocks(html) do
    pattern = ~r/<pre><code(?: class="([^"]+)")?>(.*?)<\/code><\/pre>/s
    matches = Regex.scan(pattern, html, capture: :all_but_first)
    parts = Regex.split(pattern, html)
    total = length(matches)

    Enum.zip(parts, matches ++ [nil])
    |> Enum.with_index()
    |> Enum.reduce("", fn {{part, match}, idx}, acc ->
      replacement =
        case match do
          nil ->
            ""

          [class, body] ->
            build_code_block(class, body, total, idx)
        end

      acc <> part <> replacement
    end)
  end

  defp build_code_block(class, body, total, idx) do
    language = normalize_language(class)
    safe_copy = escape_attribute(body)

    lang_class =
      if total == 1 and idx == 0,
        do: "ui-code-block-lang",
        else: "code-block-lang"

    copy_class =
      if total == 1 and idx == 0,
        do: "ui-code-block-copy",
        else: "code-block-copy"

    """
    <div class="ui-code-block" data-language="#{language}">
      <div class="code-block-header">
        <span class="#{lang_class}">#{language}</span>
        <button type="button" class="#{copy_class}" data-copy-text="#{safe_copy}">Copy</button>
      </div>
      <pre><code#{code_class_attr(class)}>#{body}</code></pre>
    </div>
    """
    |> String.trim()
  end

  defp normalize_language(nil), do: "text"

  defp normalize_language(class) do
    class
    |> String.split()
    |> List.first("text")
    |> String.replace_prefix("language-", "")
    |> case do
      "" -> "text"
      value -> value
    end
  end

  defp code_class_attr(nil), do: ""
  defp code_class_attr(class), do: ~s( class="#{class}")

  defp escape_attribute(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("\"", "&quot;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
