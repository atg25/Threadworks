defmodule ChatAppWeb.ChatLiveSettingsTest do
  # async: false — modifies Application env to swap openai_module
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias ChatApp.Conversations

  describe "toggle_settings" do
    test "toggle_settings opens and closes the drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Drawer should not be visible initially
      refute has_element?(view, "[data-settings-drawer]")

      # Click settings button to open
      view |> element("button[phx-click='toggle_settings']") |> render_click()
      assert has_element?(view, "[data-settings-drawer]")

      # Click again to close
      view |> element("button[phx-click='toggle_settings']") |> render_click()
      refute has_element?(view, "[data-settings-drawer]")
    end
  end

  describe "save_settings" do
    test "save_settings persists model + system_prompt + temperature", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Get current conversation id from assigns
      conv_id = :sys.get_state(view.pid).socket.assigns.current_conversation_id

      # Open settings
      view |> element("button[phx-click='toggle_settings']") |> render_click()

      # Submit the form
      view
      |> element("form[phx-submit='save_settings']")
      |> render_submit(%{
        "settings" => %{
          "model" => "gpt-4o-mini",
          "system_prompt" => "Be terse.",
          "temperature" => "0.4"
        }
      })

      # Verify DB persisted correctly
      conv = Conversations.get_conversation!(conv_id)
      assert conv.model == "gpt-4o-mini"
      assert conv.system_prompt == "Be terse."
      assert_in_delta conv.temperature, 0.4, 0.001

      # Drawer should be closed and flash shown
      refute has_element?(view, "[data-settings-drawer]")
      assert has_element?(view, "[data-settings-saved]")
    end

    test "save_settings rejects invalid temperature and keeps drawer open", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open settings
      view |> element("button[phx-click='toggle_settings']") |> render_click()

      # Submit with out-of-range temperature
      view
      |> element("form[phx-submit='save_settings']")
      |> render_submit(%{
        "settings" => %{
          "model" => "gpt-4o-mini",
          "system_prompt" => "",
          "temperature" => "3.0"
        }
      })

      # Drawer stays open; error flash is shown
      assert has_element?(view, "[data-settings-drawer]")
      html = render(view)
      assert html =~ "temperature" or html =~ "invalid"
    end
  end

  describe "send_message uses saved settings" do
    test "send_message uses the saved settings in the OpenAI request body", %{conn: conn} do
      parent = self()

      # Override openai_module to ChatApp.OpenAI so Req.Test can capture the body
      original_module = Application.get_env(:chat_app, :openai_module)
      Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI)

      on_exit(fn ->
        Application.put_env(:chat_app, :openai_module, original_module)
      end)

      Req.Test.stub(ChatApp.OpenAI, fn plug_conn ->
        {:ok, body_bin, plug_conn} = Plug.Conn.read_body(plug_conn)
        send(parent, {:captured_body, Jason.decode!(body_bin)})
        Req.Test.text(plug_conn, "data: [DONE]\n\n")
      end)

      {:ok, view, _html} = live(conn, "/")

      # Open settings and save
      view |> element("button[phx-click='toggle_settings']") |> render_click()

      view
      |> element("form[phx-submit='save_settings']")
      |> render_submit(%{
        "settings" => %{
          "model" => "gpt-4o-mini",
          "system_prompt" => "Be terse.",
          "temperature" => "0.4"
        }
      })

      # Send a message
      view
      |> element("form[data-chat-composer-form]")
      |> render_submit(%{"input" => "hello"})

      assert_receive {:captured_body, body}, 2000

      assert body["model"] == "gpt-4o-mini"
      assert_in_delta body["temperature"], 0.4, 0.001

      messages = body["messages"]
      assert Enum.any?(messages, &(&1["role"] == "system" and &1["content"] == "Be terse."))
    end
  end
end
