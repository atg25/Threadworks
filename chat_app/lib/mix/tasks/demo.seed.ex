defmodule Mix.Tasks.Demo.Seed do
  @moduledoc "Seeds the local dev database with a deterministic Threadworks demo catalog."
  use Mix.Task

  @shortdoc "Seeds local demo user, catalog, search indexes, saved items, and preferences"

  @impl Mix.Task
  def run(_args) do
    if Mix.env() != :dev do
      Mix.raise("mix demo.seed is dev-only; run it without MIX_ENV or with MIX_ENV=dev")
    end

    Mix.Task.run("app.start")

    %{user: user, items: items} = ChatApp.Demo.seed!()

    Mix.shell().info("""
    Seeded Threadworks demo data.
    User: #{user.email}
    Items: #{length(items)}
    Login: http://localhost:4000/dev/demo-login
    """)
  end
end
