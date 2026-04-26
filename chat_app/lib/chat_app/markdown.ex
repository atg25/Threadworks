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
  end
end
