defmodule ChatApp.OpenAI.SSE do
  @moduledoc """
  Stateful SSE chunk parser for OpenAI streaming responses.

  Req delivers raw TCP chunks. A chunk may contain multiple `data:` lines, or
  a line may be split across two chunks. The `acc` argument carries the
  incomplete trailing line from one call to the next.

  Returns `{:cont, leftover}` — the leftover is passed as `acc` on the next call.
  """

  @doc """
  Parse one raw binary chunk. `acc` is the incomplete line from the prior chunk.
  Sends `{:stream_token, token}` to `lv_pid` for each content fragment found.
  Returns `{:cont, new_acc}`.
  """
  def parse_sse_chunk(raw, acc, lv_pid) do
    combined = (acc || "") <> raw

    {lines, leftover} =
      combined
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing(&1, "\r"))
      |> split_lines_and_remainder()

    Enum.each(lines, &dispatch_line(&1, lv_pid))

    {:cont, leftover}
  end

  @doc """
  Splits a list of strings (from `String.split("\\n")`) into
  `{complete_lines, partial_last_line}`.

  The last element is always treated as potentially incomplete (it has no
  trailing newline). Empty strings in the complete portion are filtered out.
  """
  def split_lines_and_remainder([]), do: {[], ""}
  def split_lines_and_remainder([single]), do: {[], single}

  def split_lines_and_remainder(parts) do
    {init, [last]} = Enum.split(parts, length(parts) - 1)
    complete = Enum.reject(init, &(&1 == ""))
    {complete, last}
  end

  # ── private ──────────────────────────────────────────────────

  defp dispatch_line("data: [DONE]", _pid), do: :ok

  defp dispatch_line("data: " <> json, pid) do
    with {:ok, body} <- Jason.decode(json) do
      # Dispatch stream_usage if the chunk contains a usage block.
      if is_map(body["usage"]) do
        send(pid, {:stream_usage, body["usage"]})
      end

      # Dispatch stream_token for content deltas.
      content = get_in(body, ["choices", Access.at(0), "delta", "content"])
      if is_binary(content), do: send(pid, {:stream_token, content})
    end

    :ok
  end

  defp dispatch_line(_other, _pid), do: :ok
end
