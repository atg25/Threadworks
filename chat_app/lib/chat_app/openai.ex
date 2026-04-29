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
  @max_retries 2

  @doc """
  Posts a streaming chat request. Sends `{:stream_token, token}` messages to
  `lv_pid` as chunks arrive, then sends `:stream_done` when the request ends
  with a 2xx status. Sends `{:stream_error, reason}` on non-2xx HTTP status,
  transport error, or exception.

  Retries transport-level failures and 5xx responses up to `@max_retries` times
  with exponential backoff. 4xx responses are not retried.
  """
  def stream(messages, lv_pid, opts \\ %{}) do
    do_stream(messages, lv_pid, opts, 0)
  end

  defp do_stream(messages, lv_pid, opts, attempt) do
    case attempt_stream(messages, lv_pid, opts) do
      :ok ->
        :ok

      {:retryable, reason} when attempt < @max_retries ->
        Logger.warning(
          "OpenAI retryable failure (attempt: #{attempt + 1}, reason: #{inspect(reason)}, message_count: #{length(messages)})",
          attempt: attempt + 1,
          reason: inspect(reason),
          message_count: length(messages)
        )

        send(lv_pid, {:stream_retrying, attempt})
        Process.sleep(backoff_ms(attempt))
        do_stream(messages, lv_pid, opts, attempt + 1)

      {:retryable, reason} ->
        # Exhausted all retries
        Logger.error(
          "OpenAI stream failed after #{@max_retries} retries (reason: #{inspect(reason)}, message_count: #{length(messages)})",
          reason: inspect(reason),
          message_count: length(messages)
        )

        send(lv_pid, {:stream_error, error_message(reason)})

      {:fatal, reason} ->
        send(lv_pid, {:stream_error, reason})
    end
  end

  defp attempt_stream(messages, lv_pid, opts) do
    result =
      try do
        body =
          %{
            model: Map.get(opts, :model) || openai_model(),
            stream: true,
            stream_options: %{include_usage: true},
            messages: build_messages(messages, opts)
          }
          |> maybe_put(:temperature, Map.get(opts, :temperature))

        base_opts = [
          headers: [{"Authorization", "Bearer #{api_key()}"}],
          json: body,
          receive_timeout: Application.get_env(:chat_app, :openai_receive_timeout, 120_000),
          into: fn {:data, chunk}, {req, resp} ->
            buf = Map.get(req.private, :sse_buf, "")
            {:cont, new_buf} = SSE.parse_sse_chunk(chunk, buf, lv_pid)
            {:cont, {Req.Request.put_private(req, :sse_buf, new_buf), resp}}
          end
        ]

        req_opts = Keyword.merge(base_opts, Application.get_env(:chat_app, :req_options, []))

        Req.post(api_url(), req_opts)
      rescue
        error ->
          Logger.error(
            "OpenAI exception (error: #{Exception.message(error)}, message_count: #{length(messages)})",
            error: Exception.message(error),
            message_count: length(messages)
          )

          {:exception, error}
      end

    case result do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        send(lv_pid, :stream_done)
        :ok

      {:ok, %Req.Response{status: status}} when status in 400..500 ->
        Logger.warning(
          "OpenAI non-2xx response (status: #{status}, message_count: #{length(messages)})",
          status: status,
          message_count: length(messages)
        )

        {:fatal, "HTTP #{status}"}

      {:ok, %Req.Response{status: status}} when status in 501..599 ->
        Logger.warning(
          "OpenAI non-2xx response (status: #{status}, message_count: #{length(messages)})",
          status: status,
          message_count: length(messages)
        )

        {:retryable, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error(
          "OpenAI transport error (reason: #{inspect(reason)}, message_count: #{length(messages)})",
          reason: inspect(reason),
          message_count: length(messages)
        )

        {:retryable, reason}

      {:exception, error} ->
        {:fatal, Exception.message(error)}
    end
  end

  defp error_message(%{__exception__: true} = e), do: Exception.message(e)
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)

  def backoff_ms(attempt) when is_integer(attempt) and attempt >= 0 do
    capped = min(attempt, @max_retries)
    round(250 * :math.pow(2, capped))
  end

  defp build_messages(messages, opts) do
    base_messages =
      Enum.map(messages, fn %{role: role, content: content} ->
        %{role: to_string(role), content: content}
      end)

    case Map.get(opts, :system_prompt) do
      value when is_binary(value) and value != "" ->
        [%{role: "system", content: value} | base_messages]

      _ ->
        base_messages
    end
  end

  defp maybe_put(body, _key, value) when value in [nil, ""], do: body
  defp maybe_put(body, key, value), do: Map.put(body, key, value)

  # Read from Application env so tests can override with a local URL.
  defp api_url do
    Application.get_env(:chat_app, :openai_api_url, @default_api_url)
  end

  defp openai_model, do: Application.get_env(:chat_app, :openai_model, "gpt-4o")

  defp api_key, do: Application.fetch_env!(:chat_app, :openai_api_key)
end
