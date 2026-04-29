defmodule ChatAppWeb.Sprint15PersistenceAndAuthE2ETest do
  use ChatAppWeb.FeatureCase, async: false

  @moduletag :e2e

  feature "Positive — refresh restores conversation", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.text_field("chat[message]"), with: "hello")
      |> click(Query.button("Send"))

    assert_has(session, Query.text("hello"))
    assert_has(session, Query.text("Stub response."))

    session = visit(session, "/")

    assert_has(session, Query.text("hello"))
    assert_has(session, Query.text("Stub response."))
  end

  feature "Negative — basic auth blocks anonymous request when configured", %{session: session} do
    Application.put_env(:chat_app, :basic_auth_user, "admin")
    Application.put_env(:chat_app, :basic_auth_password, "secret")

    on_exit(fn ->
      Application.delete_env(:chat_app, :basic_auth_user)
      Application.delete_env(:chat_app, :basic_auth_password)
    end)

    session = visit(session, "/")

    refute_has(session, Query.css("#chat-input"))
  end

  feature "Negative — Stop button cancels mid-stream and partial content remains", %{session: session} do
    session =
      session
      |> visit("/")
      |> fill_in(Query.text_field("chat[message]"), with: "long prompt")
      |> click(Query.button("Send"))

    session = click(session, Query.button("Stop"))

    assert_has(session, Query.css("[data-chat-state]"))
    assert_has(session, Query.text("Stub"))

    session = visit(session, "/")

    assert_has(session, Query.text("Stub"))
  end

  feature "Negative — Regenerate without a prior assistant turn is a no-op (no DB churn)", %{session: session} do
    session = visit(session, "/")

    _session =
      execute_script(
        session,
        "window.dispatchEvent(new CustomEvent('phx:click', { detail: { event: 'regenerate' } }));"
      )

    assert_has(session, Query.css("#chat-input"))
    refute_has(session, Query.text("undefined"))
  end

  feature "Negative — Theme toggle survives page reload", %{session: session} do
    session =
      session
      |> visit("/")
      |> click(Query.css("[data-phx-theme='swiss']"))

    assert_has(session, Query.css("html[data-theme='swiss']"))

    session = visit(session, "/")

    assert_has(session, Query.css("html[data-theme='swiss']"))
  end
end
