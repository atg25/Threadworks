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

  def stream(messages, pid, _opts \\ %{}) do
    last_user_content =
      messages
      |> Enum.reverse()
      |> Enum.find_value("", fn
        %{role: :user, content: content} when is_binary(content) -> content
        %{"role" => "user", "content" => content} when is_binary(content) -> content
        _ -> nil
      end)

    downcased = String.downcase(last_user_content)

    if String.contains?(downcased, "stream me") do
      send(pid, {:stream_token, "Stub "})
      Process.sleep(450)
      send(pid, {:stream_token, "response."})
      send(pid, :stream_done)
    else
      if String.contains?(downcased, "trigger delayed stream") do
        Process.sleep(450)
        send(pid, {:stream_token, "Stub "})
        send(pid, {:stream_token, "response."})
        send(pid, :stream_done)
      else
        if String.contains?(downcased, "code backgrounds") do
          send(
            pid,
            {:stream_token, "Paragraph with `inline` code.\n\n```elixir\nIO.puts(\"hi\")\n```"}
          )

          send(pid, :stream_done)
        else
          if String.contains?(downcased, "color inheritance") do
            send(pid, {:stream_token, "# Header\n\nParagraph with **bold** text."})
            send(pid, :stream_done)
          else
            if String.contains?(downcased, "show code") do
              send(pid, {:stream_token, "```elixir\nIO.puts(\"hi\")\n```"})
              send(pid, :stream_done)
            else
              send(pid, {:stream_token, "Stub "})
              send(pid, {:stream_token, "response."})
              send(pid, :stream_done)
            end
          end
        end
      end
    end
  end
end
