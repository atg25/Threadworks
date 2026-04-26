defmodule ChatApp.OpenAI.E2EStub do
  @moduledoc """
  Deterministic OpenAI stub for Wallaby E2E feature tests.

  Sends two tokens ("Stub " and "response.") followed immediately by
  :stream_done, all synchronously in the caller's process. This makes
  streaming assertions reliable without any timing uncertainty or real
  network calls.

  The existing `ChatApp.OpenAI.Stub` sends a single empty token and
  never sends :stream_done (unit tests control timing manually).
  This stub is used exclusively by `ChatAppWeb.FeatureCase` which
  switches :openai_module at runtime for the duration of each E2E test.
  """

  def stream(_messages, pid) do
    send(pid, {:stream_token, "Stub "})
    send(pid, {:stream_token, "response."})
    send(pid, :stream_done)
  end
end
