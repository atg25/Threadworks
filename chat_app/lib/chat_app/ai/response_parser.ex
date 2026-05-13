defmodule ChatApp.AI.ResponseParser do
  @moduledoc false

  @doc """
  Accumulates streamed LLM chunks and extracts card structs when a complete
  JSON object is found in the buffer.

  Returns `{cards, remaining_buffer}`.
  """
  def parse(chunk, buffer) do
    accumulated = buffer <> chunk
    do_parse(accumulated)
  end

  # Scans for a balanced JSON object, decodes it, and retries from after the
  # failed candidate when the first `{`-rooted string is not valid JSON. This
  # handles LLM prose that contains `{word}` before the real cards block.
  defp do_parse(text) do
    case find_json_object(text) do
      nil ->
        {[], text}

      {json_string, after_json} ->
        case Jason.decode(json_string) do
          {:ok, %{"cards" => raw_cards}} when is_list(raw_cards) ->
            cards = Enum.flat_map(raw_cards, &coerce_card/1)
            {cards, after_json}

          {:ok, _} ->
            # Valid JSON but no "cards" key — skip this object and keep scanning.
            do_parse(after_json)

          {:error, _} ->
            # Malformed JSON: this candidate is corrupt. Discard it and retry
            # from the rest of the buffer so a later `{` can still be found.
            do_parse(after_json)
        end
    end
  end

  # Scans `text` for the first `{` and attempts to extract a complete JSON
  # object by tracking brace depth. Returns `{json_string, remainder}` when
  # a balanced object is found, or `nil` when no complete object is present.
  defp find_json_object(text) do
    case :binary.match(text, "{") do
      :nomatch ->
        nil

      {start, _} ->
        suffix = binary_part(text, start, byte_size(text) - start)

        case extract_balanced(suffix) do
          nil -> nil
          {json, rest} -> {json, rest}
        end
    end
  end

  # Walks `text` character by character tracking `{` / `}` depth and whether
  # the cursor is inside a string literal. Returns `{json_string, remainder}`
  # when depth reaches zero, or `nil` if no balanced object is found.
  defp extract_balanced(text) do
    do_extract(text, 0, false, false, 0, byte_size(text))
  end

  defp do_extract(_text, _depth, _in_string, _escape, pos, size) when pos >= size, do: nil

  defp do_extract(text, depth, in_string, escape, pos, size) do
    <<_head::binary-size(pos), char, _rest::binary>> = text

    cond do
      escape ->
        do_extract(text, depth, in_string, false, pos + 1, size)

      in_string and char == ?\\ ->
        do_extract(text, depth, in_string, true, pos + 1, size)

      in_string and char == ?" ->
        do_extract(text, depth, false, false, pos + 1, size)

      in_string ->
        do_extract(text, depth, true, false, pos + 1, size)

      char == ?{ ->
        do_extract(text, depth + 1, false, false, pos + 1, size)

      char == ?} and depth == 1 ->
        json = binary_part(text, 0, pos + 1)
        rest = binary_part(text, pos + 1, size - pos - 1)
        {json, rest}

      char == ?} ->
        do_extract(text, depth - 1, false, false, pos + 1, size)

      char == ?" ->
        do_extract(text, depth, true, false, pos + 1, size)

      true ->
        do_extract(text, depth, false, false, pos + 1, size)
    end
  end

  defp coerce_card(%{"item_id" => item_id, "reason" => reason}) do
    case coerce_item_id(item_id) do
      {:ok, id} -> [%{item_id: id, reason: reason}]
      :error -> []
    end
  end

  defp coerce_card(_), do: []

  defp coerce_item_id(id) when is_integer(id) and id > 0, do: {:ok, id}
  defp coerce_item_id(id) when is_integer(id), do: :error

  defp coerce_item_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp coerce_item_id(_), do: :error
end
