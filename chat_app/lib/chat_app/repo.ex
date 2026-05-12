defmodule ChatApp.Repo do
  use Ecto.Repo,
    otp_app: :chat_app,
    adapter: Ecto.Adapters.SQLite3

  # Loads the sqlite_vec extension on each DB connection. Done here rather
  # than in config.exs because SqliteVec.path/0 needs deps compiled to resolve.
  @impl true
  def init(_, opts) do
    {:ok, Keyword.put(opts, :load_extensions, [SqliteVec.path()])}
  end
end
