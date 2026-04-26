defmodule ChatApp.Sprint12ImmediateFixesResilienceUnitTest do
  use ExUnit.Case, async: false

  alias ChatAppWeb.ChatLive

  test "Hammer key derivation is stable for a session_id" do
    session_id = "abc123"
    k1 = ChatLive.rate_limit_key_for_session(session_id)
    k2 = ChatLive.rate_limit_key_for_session(session_id)
    assert k1 == "chatlive:#{session_id}"
    assert k1 == k2
  end

  test "error assign shape: each entry has :for_index and :reason keys" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        messages: [%{role: :user, content: "Q"}],
        errors: [],
        is_sending: true,
        stream_buffer: "partial"
      }
    }

    {:noreply, updated_socket} = ChatLive.handle_info({:stream_error, "x"}, socket)
    errors = Map.get(updated_socket.assigns, :errors, [])

    assert length(errors) >= 1
    assert Enum.all?(errors, &Map.has_key?(&1, :for_index))
    assert Enum.all?(errors, &Map.has_key?(&1, :reason))
    assert Enum.all?(errors, &(Map.keys(&1) |> Enum.sort() == [:for_index, :reason]))
    assert Enum.all?(errors, &(is_integer(&1.for_index) and is_binary(&1.reason)))
  end

  test "terminate/2 with stream_task_pid: nil is a no-op" do
    socket = %Phoenix.LiveView.Socket{assigns: %{stream_task_pid: nil}}
    assert :ok == ChatLive.terminate(:shutdown, socket)
  end
end
