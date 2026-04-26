defmodule ChatApp.OpenAI do
  @moduledoc """
  Streams OpenAI Chat Completions SSE to a target process.
  Pure with respect to the calling process — no process-dictionary state.

  ## Configuration

  `:req_options` overrides the request options built by this module.
  Precedence is `Keyword.merge(base_opts, req_options)` — the override wins.
  """

  alias ChatApp.OpenAI.SSE

  require Logger

  @default_api_url "https://api.openai.com/v1/chat/completions"

  @doc """
  Posts a streaming chat request. Sends `{:stream_token, token}` messages to
  `lv_pid` as chunks arrive, then sends `:stream_done` when the request ends
  with a 2xx status. Sends `{:stream_error, reason}` on non-2xx HTTP status,
  transport error, or exception.
  """
  def stream(messages, lv_pid) do
    body = %{
      model: openai_model(),
      stream: true,
      messages:
        Enum.map(messages, fn %{role: role, content: content} ->
          %{role: to_string(role), content: content}
        end)
    }

    base_opts = [
      headers: [{"Authorization", "Bearer #{api_key()}"}],
      json: body,
      receive_timeout: Application.get_env(:chat_app, :openai_receive_timeout, 120_000),
      into: fn {:data, chunk}, {req, resp} ->
        # SSE leftover line is carried in req.private[:sse_buf] across chunk callbacks.
        buf = Map.get(req.private, :sse_buf, "")
        {:cont, new_buf} = SSE.parse_sse_chunk(chunk, buf, lv_pid)
        {:cont, {Req.Request.put_private(req, :sse_buf, new_buf), resp}}
      end
    ]

    opts = Keyword.merge(base_opts, Application.get_env(:chat_app, :req_options, []))

    case Req.post(api_url(), opts) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        send(lv_pid, :stream_done)

      {:ok, %Req.Response{status: status}} ->
        Logger.warning(
          "OpenAI non-2xx response (status: #{status}, message_count: #{length(messages)})",
          status: status,
          message_count: length(messages)
        )

        send(lv_pid, {:stream_error, "HTTP #{status}"})

      {:error, reason} ->
        Logger.error(
          "OpenAI transport error (reason: #{inspect(reason)}, message_count: #{length(messages)})",
          reason: inspect(reason),
          message_count: length(messages)
        )

        send(lv_pid, {:stream_error, error_message(reason)})
    end
  rescue
    error ->
      Logger.error(
        "OpenAI exception (error: #{Exception.message(error)}, message_count: #{length(messages)})",
        error: Exception.message(error),
        message_count: length(messages)
      )

      send(lv_pid, {:stream_error, Exception.message(error)})
  end

  defp error_message(%{__exception__: true} = e), do: Exception.message(e)
  defp error_message(reason), do: inspect(reason)

  # Read from Application env so tests can override with a local URL.
  defp api_url do
    Application.get_env(:chat_app, :openai_api_url, @default_api_url)
  end

  defp openai_model, do: Application.get_env(:chat_app, :openai_model, "gpt-4o")

  defp api_key, do: Application.fetch_env!(:chat_app, :openai_api_key)
end
