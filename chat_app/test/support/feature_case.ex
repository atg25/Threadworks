defmodule ChatAppWeb.FeatureCase do
  @moduledoc """
  ExUnit case template for Wallaby end-to-end feature tests.

  Each test receives a browser `session` in its context map.
  The setup block switches the global :openai_module to
  `ChatApp.OpenAI.E2EStub`, which sends "Stub response." across two
  tokens then immediately sends :stream_done — making the streaming
  path fast and deterministic without any real network calls.

  async: false is required because:
    1. Wallaby feature tests run in real browser sessions (side-effects).
    2. The :openai_module Application env change is global state.
  """

  use ExUnit.CaseTemplate

  alias ChatApp.Conversations.Conversation
  alias ChatApp.Repo

  using do
    quote do
      use Wallaby.Feature
      import Wallaby.Query
      import Wallaby.Browser
      alias Wallaby.Query
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ChatApp.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(ChatApp.Repo, {:shared, self()})

    # Keep feature tests isolated: reset persisted conversation rows between tests.
    Repo.delete_all(Conversation)

    # Switch to E2EStub for the duration of the test, restore on exit.
    original_module = Application.get_env(:chat_app, :openai_module)

    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI.E2EStub)

    on_exit(fn ->
      if original_module do
        Application.put_env(:chat_app, :openai_module, original_module)
      else
        Application.delete_env(:chat_app, :openai_module)
      end
    end)

    # Wallaby.Feature injects a :session key; this setup merges
    # our keys into whatever Wallaby already put in the context.
    {:ok, tags}
  end
end
