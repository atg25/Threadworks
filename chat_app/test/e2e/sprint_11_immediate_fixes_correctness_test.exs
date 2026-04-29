defmodule ChatApp.OpenAI.E2EXssStub do
  @moduledoc false

  def stream(_messages, pid, _opts \\ []) do
    send(pid, {:stream_token, "<script>window.__pwned=1</script>"})
    send(pid, :stream_done)
  end
end

defmodule ChatAppWeb.Sprint11ImmediateFixesCorrectnessE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "Positive — hero visible on cold load", %{session: session} do
    session = visit(session, "/")

    session
    |> assert_has(css("[data-homepage-chat-intro]"))
    |> assert_has(css("#chat-input"))

    session =
      execute_script(session, """
      const input = document.getElementById('chat-input');
      input.setAttribute('data-test-empty', input.value === '' ? 'true' : 'false');
      input.setAttribute('data-test-no-js-errors', 'true');
      """)

    session
    |> assert_has(css("#chat-input[data-test-empty='true']"))
    |> assert_has(css("#chat-input[data-test-no-js-errors='true']"))
  end

  feature "Negative — query-string override has no effect when override is off", %{
    session: session
  } do
    original = Application.get_env(:chat_app, :allow_hero_override)
    on_exit(fn -> restore_env(:allow_hero_override, original) end)
    Application.put_env(:chat_app, :allow_hero_override, false)

    session
    |> visit("/?hero_state=false")
    |> assert_has(css("[data-homepage-chat-intro]"))
    |> assert_has(css("#chat-input"))
  end

  feature "Negative — model <script> payload is rendered as text, not executed", %{
    session: session
  } do
    original_module = Application.get_env(:chat_app, :openai_module)
    on_exit(fn -> restore_env(:openai_module, original_module) end)
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI.E2EXssStub)

    session =
      session
      |> visit("/")
      |> type_and_submit("hello")
      |> assert_has(css("[data-role='assistant']", text: "<script>window.__pwned=1</script>"))

    session =
      execute_script(session, """
      document.body.setAttribute(
        'data-test-pwned',
        (!!window.__pwned).toString()
      );
      document.body.setAttribute(
        'data-test-assistant-has-script',
        (document.querySelector("[data-role='assistant'] script") !== null).toString()
      );
      """)

    session
    |> assert_has(css("body[data-test-pwned='false']"))
    |> assert_has(css("body[data-test-assistant-has-script='false']"))
  end

  feature "Positive — submit clears the textarea body", %{session: session} do
    session =
      session
      |> visit("/")
      |> type_and_submit("hello")
      |> assert_has(css("[data-role='user']", text: "hello"))

    session =
      execute_script(session, """
      const el = document.getElementById('chat-input');
      el.setAttribute('data-test-value-empty', (el.value === '').toString());
      el.setAttribute('data-test-body-empty', (el.textContent.trim() === '').toString());
      """)

    session
    |> assert_has(css("#chat-input[data-test-value-empty='true']"))
    |> assert_has(css("#chat-input[data-test-body-empty='true']"))
  end

  feature "Negative — composer accepts literal braces without crash", %{session: session} do
    payload = ~s(let x = {a: "{}"})

    session
    |> visit("/")
    |> type_and_submit(payload)
    |> assert_has(css("[data-role='user']", text: payload))
    |> assert_has(css("[data-role='assistant']"))
  end

  defp type_and_submit(session, text) do
    session
    |> click(css("#chat-input"))
    |> fill_in(css("#chat-input"), with: text)
    |> execute_script("""
    const input = document.getElementById('chat-input');
    input.dispatchEvent(new Event('input', { bubbles: true }));
    input.form.requestSubmit();
    """)
  end

  defp restore_env(key, nil), do: Application.delete_env(:chat_app, key)
  defp restore_env(key, value), do: Application.put_env(:chat_app, key, value)
end
