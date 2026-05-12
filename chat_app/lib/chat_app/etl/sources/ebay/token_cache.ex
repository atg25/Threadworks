defmodule ChatApp.ETL.Sources.Ebay.TokenCache do
  use GenServer

  @table :ebay_token_cache
  @token_path "/identity/v1/oauth2/token"
  @oauth_scope "https://api.ebay.com/oauth/api_scope"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  # Fast path — reads directly from ETS, no GenServer round-trip.
  def get do
    case :ets.lookup(@table, :token) do
      [{:token, token, expires_at}] -> {token, expires_at}
      [] -> :empty
    end
  end

  def put(token, expires_at) do
    :ets.insert(@table, {:token, token, expires_at})
    :ok
  end

  # Serialized via GenServer call to prevent thundering-herd on concurrent callers.
  def refresh_if_stale do
    GenServer.call(__MODULE__, :refresh_if_stale, 15_000)
  end

  @doc false
  # Public only for test isolation; do not call from production code.
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:refresh_if_stale, _from, state) do
    # Double-checked lock: re-read ETS now that we hold the serialisation lock.
    result =
      try do
        case get() do
          {token, expires_at} ->
            if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
              token
            else
              do_refresh_token()
            end

          :empty ->
            do_refresh_token()
        end
      rescue
        # Network failure or unexpected eBay response — keep the GenServer alive
        # and surface the error to the caller instead of crashing.
        _ -> {:error, :token_refresh_failed}
      end

    {:reply, result, state}
  end

  defp do_refresh_token do
    base_url = Application.get_env(:chat_app, :ebay_api_base_url)
    app_id = Application.get_env(:chat_app, :ebay_app_id)
    cert_id = Application.get_env(:chat_app, :ebay_cert_id)
    credentials = Base.encode64("#{app_id}:#{cert_id}")

    %{body: body} =
      Req.post!("#{base_url}#{@token_path}",
        retry: false,
        headers: [{"authorization", "Basic #{credentials}"}],
        form: [
          grant_type: "client_credentials",
          scope: @oauth_scope
        ]
      )

    token = body["access_token"]
    expires_in = body["expires_in"]
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)
    put(token, expires_at)
    token
  end
end
