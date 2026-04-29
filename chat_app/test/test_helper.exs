ExUnit.start(exclude: [:real_api])

Ecto.Adapters.SQL.Sandbox.mode(ChatApp.Repo, :manual)
Code.ensure_loaded(ChatApp.Conversations)
Code.ensure_loaded(ChatApp.Conversations.Conversation)
Code.ensure_loaded(ChatApp.Conversations.Message)
Code.ensure_loaded(ChatAppWeb.Router)
Code.ensure_loaded(ChatApp.Chat)
Code.ensure_loaded(ChatAppWeb.ChatLive)

excluded_tags =
  ExUnit.configuration()[:exclude]
  |> List.wrap()
  |> Enum.map(fn
    {tag, _} when is_atom(tag) -> tag
    tag when is_atom(tag) -> tag
    other -> other
  end)

if :e2e not in excluded_tags do
  {:ok, _} = Application.ensure_all_started(:wallaby)
  Application.put_env(:wallaby, :base_url, ChatAppWeb.Endpoint.url())
end
