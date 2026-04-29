defmodule ChatApp.OpenAI.Stub do
  @moduledoc """
  Unit-test stand-in for `ChatApp.OpenAI`.

  Configured in `config/test.exs` via `config :chat_app, :openai_module,
  ChatApp.OpenAI.Stub`. Unlike `ChatApp.OpenAI.E2EStub`, this stub does
  **not** send `:stream_done` on its own — individual tests send the
  `{:stream_token, ...}` / `:stream_done` / `{:stream_error, ...}`
  messages themselves to exercise precise state-machine transitions.
  """

  @doc """
  Sends an empty token without stream_done. Tests must explicitly send
  `{:stream_token, content}` and `:stream_done` to control timing.
  Sending an empty string keeps stream_buffer at "" so animate-pulse
  remains visible until a real token arrives.
  """
  def stream(_messages, pid, _opts \\ %{}) do
    send(pid, {:stream_token, ""})
    Process.sleep(100)
  end
end
