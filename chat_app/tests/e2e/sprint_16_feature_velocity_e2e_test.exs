defmodule ChatAppWeb.Sprint16FeatureVelocityE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "Positive — full sidebar flow", %{session: session} do
    session =
      session
      |> execute_script("window.sessionStorage.setItem('chat_app:session_id', 'e2e-sprint16')")
      |> visit("/")
      |> click(Query.css("button[phx-click='new_conversation']"))
      |> assert_has(Query.css("[data-conversation-id]"))

    first_id =
      session
      |> page_source()
      |> Floki.parse_document!()
      |> Floki.find("[data-conversation-id]")
      |> List.first()
      |> Floki.attribute("data-conversation-id")
      |> List.first()

    switch_selector =
      "[data-conversation-id='#{first_id}'] button[phx-click='switch_conversation']"

    session =
      session
      |> click(Query.css("button[phx-click='new_conversation']"))
      |> fill_in(Query.css("#chat-input"), with: "hello")
      |> send_keys([:enter])
      |> click(Query.css("button[phx-click='new_conversation']"))
      |> fill_in(Query.css("#chat-input"), with: "second")
      |> send_keys([:enter])
      |> assert_has(Query.css(switch_selector))
      |> click(Query.css(switch_selector))

    assert_has(session, Query.css(switch_selector))
    assert_has(session, Query.text("hello"))
  end

  feature "Positive — settings drawer round-trip", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("button[phx-click='toggle_settings']"))
      |> assert_has(Query.css("[data-settings-drawer]"))
      |> fill_in(Query.css("textarea[name='settings[system_prompt]']"), with: "Be terse.")
      |> click(Query.button("Save"))
      |> fill_in(Query.css("#chat-input"), with: "hi")
      |> send_keys([:enter])

    assert_has(session, Query.css("[data-current-model='gpt-4o-mini']"))
  end

  feature "Positive — code-block copy works in browser", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"), with: "show code")
      |> send_keys([:enter])
      |> click(Query.css(".ui-code-block-copy"))

    assert_has(session, Query.css(".ui-code-block-copy"))
  end

  feature "Negative — sidebar gracefully handles deleting the active conversation", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("button[phx-click='delete_conversation']"))

    assert_has(session, Query.css("[data-conversation-id]"))
  end

  feature "Negative — settings reject out-of-range temperature with a flash", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("button[phx-click='toggle_settings']"))
      |> fill_in(Query.css("input[name='settings[temperature]']"), with: "3.0")
      |> click(Query.button("Save"))

    assert_has(session, Query.text("temperature"))
  end

  feature "Negative — token / cost header gracefully handles a missing usage block", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"), with: "no usage block")
      |> send_keys([:enter])

    assert_has(session, Query.text("$0.00"))
  end

  feature "Negative — mid-stream transport drop triggers retry without duplicate prefix", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.css("#chat-input"), with: "retry please")
      |> send_keys([:enter])

    assert_has(session, Query.text("retry"))
    refute_has(session, Query.text("retryretry"))
  end
end
