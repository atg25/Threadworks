defmodule ChatAppWeb.Sprint11ImmediateFixesCorrectnessIntegrationTest do
  use ChatAppWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias ChatApp.OpenAI

  test "mount/3 ignores ?hero_state=false when override is off", %{conn: conn} do
    original = Application.get_env(:chat_app, :allow_hero_override)
    on_exit(fn -> restore_env(:allow_hero_override, original) end)
    Application.put_env(:chat_app, :allow_hero_override, false)

    {:ok, view, _html} = live(conn, "/?hero_state=false")
    assert has_element?(view, "[data-homepage-chat-intro]")
  end

  test "mount/3 honors ?hero_state=false when override is on", %{conn: conn} do
    original = Application.get_env(:chat_app, :allow_hero_override)
    on_exit(fn -> restore_env(:allow_hero_override, original) end)
    Application.put_env(:chat_app, :allow_hero_override, true)

    {:ok, view, _html} = live(conn, "/?hero_state=false")
    refute has_element?(view, "[data-homepage-chat-intro]")
  end

  test "assistant bubble renders escaped <script> as text", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    html = send_and_finish(view, "Q", "<script>alert(1)</script>")

    assert html =~ "&lt;script&gt;"
    refute html =~ "<script>"

    {:ok, doc} = Floki.parse_document(html)
    refute Floki.find(doc, "[data-role='assistant'] script") != []
  end

  test "OpenAI.stream/2 sends configured :openai_model in body" do
    original = Application.get_env(:chat_app, :openai_model)
    on_exit(fn -> restore_env(:openai_model, original) end)
    Application.put_env(:chat_app, :openai_model, "gpt-test-12345")

    parent = self()

    Req.Test.stub(ChatApp.OpenAI, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:captured_model, Jason.decode!(body)["model"]})
      Req.Test.text(conn, "data: [DONE]\n\n")
    end)

    OpenAI.stream([%{role: :user, content: "hello"}], self())

    assert_received {:captured_model, "gpt-test-12345"}
  end

  test "composer renders empty paired textarea on first mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    {:ok, doc} = Floki.parse_document(html)
    [textarea] = Floki.find(doc, "textarea#chat-input")

    assert String.trim(Floki.text(textarea)) == ""
    assert Floki.attribute(textarea, "value") == []
  end

  test "composer body round-trips literal { } characters", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> element("form[data-chat-composer-form]")
    |> render_change(%{"input" => "let x = {a: 1}"})

    html = render(view)
    {:ok, doc} = Floki.parse_document(html)
    [textarea] = Floki.find(doc, "textarea#chat-input")

    assert Floki.text(textarea) =~ "{a: 1}"
  end

  defp send_and_finish(view, text, response) do
    view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => text})
    send(view.pid, {:stream_token, response})
    send(view.pid, :stream_done)
    render(view)
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
