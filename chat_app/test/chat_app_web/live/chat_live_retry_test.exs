defmodule ChatAppWeb.ChatLiveRetryTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  describe ":stream_retrying LiveView handling" do
    test ":stream_retrying clears the partial assistant message from assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Send a user message to set up is_sending state
      view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => "Q"})

      pid = view.pid

      # Simulate a partial stream token (assistant bubble appears)
      send(pid, {:stream_token, "Partial response"})
      html = render(view)
      assert html =~ "Partial response"

      # Now simulate a retry event
      send(pid, {:stream_retrying, 0})
      html = render(view)

      # The partial assistant message should be gone from the rendered output
      refute html =~ "Partial response"

      # stream_buffer should be reset
      assigns = :sys.get_state(pid).socket.assigns
      assert assigns.stream_buffer == ""
      assert is_nil(assigns.assistant_message_id)
    end

    test ":stream_retrying inserts a transient error message in assigns", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Kick off a send so we're in is_sending state
      view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => "Q"})

      pid = view.pid
      send(pid, {:stream_token, "partial"})
      render(view)

      # Send retrying event
      send(pid, {:stream_retrying, 0})
      render(view)

      # errors list should have an entry for the retry
      assigns = :sys.get_state(pid).socket.assigns
      assert length(assigns.errors) >= 1

      error = List.last(assigns.errors)
      assert is_map(error)
      assert Map.has_key?(error, :reason)
    end
  end
end
