defmodule ChatApp.Chat do
  @moduledoc """
  Pure functions that manipulate the in-memory message list held in the
  `ChatAppWeb.ChatLive` socket.

  A message is a plain map: `%{role: :user | :assistant, content: binary}`.
  There is no persistence layer today — the entire conversation lives in
  the LiveView process and disappears on reconnect.
  """

  @doc """
  Appends a new assistant message, or replaces the last one if it is already
  an assistant message (used for streaming token accumulation).
  """
  def upsert_assistant_message(messages, buffer) when is_list(messages) and is_binary(buffer) do
    msg = %{role: :assistant, content: buffer}

    case messages do
      [] ->
        [msg]

      list ->
        [last | rest_reversed] = Enum.reverse(list)

        case last do
          %{role: :assistant} -> Enum.reverse([msg | rest_reversed])
          _ -> messages ++ [msg]
        end
    end
  end

  @doc """
  Formats integer cents as dollars with two decimals.
  """
  def cents_to_dollars(cents) when is_integer(cents) and cents >= 0 do
    dollars = div(cents, 100)
    remainder = rem(cents, 100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "$#{dollars}.#{remainder}"
  end
end
