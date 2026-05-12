defmodule ChatApp.ETL.Sources.Ebay do
  alias ChatApp.ETL.Sources.Ebay.TokenCache

  @search_path "/buy/browse/v1/item_summary/search"
  @clothing_category_ids "15724,11450"
  @default_limit 50

  def get_token do
    case Application.get_env(:chat_app, :ebay_app_id, "") do
      "" ->
        {:error, :missing_credentials}

      _app_id ->
        case TokenCache.get() do
          {token, expires_at} ->
            if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
              token
            else
              TokenCache.refresh_if_stale()
            end

          :empty ->
            TokenCache.refresh_if_stale()
        end
    end
  end

  def fetch_items(query, opts \\ []) do
    case get_token() do
      {:error, _} = err ->
        err

      token ->
        base_url = Application.get_env(:chat_app, :ebay_api_base_url)
        receive_timeout = Keyword.get(opts, :receive_timeout, 5_000)

        try do
          resp =
            Req.get!("#{base_url}#{@search_path}",
              retry: false,
              params: [q: query, category_ids: @clothing_category_ids, limit: @default_limit],
              headers: [{"authorization", "Bearer #{token}"}],
              receive_timeout: receive_timeout
            )

          case resp.status do
            200 -> {:ok, Map.get(resp.body, "itemSummaries", [])}
            401 -> {:error, :unauthorized}
            status -> {:error, {:http_error, status}}
          end
        rescue
          Req.TransportError -> {:error, :timeout}
        catch
          :exit, _ -> {:error, :timeout}
        end
    end
  end
end
