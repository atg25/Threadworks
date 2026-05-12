defmodule ChatApp.ETL.Sources.Depop do
  @search_path "/api/v3/search"
  @default_limit 24

  def fetch_items(query, opts \\ []) do
    base_url = Application.get_env(:chat_app, :depop_api_base_url)
    receive_timeout = Keyword.get(opts, :receive_timeout, 5_000)

    try do
      resp =
        Req.get!("#{base_url}#{@search_path}",
          retry: false,
          params: [q: query, limit: @default_limit],
          headers: [
            {"user-agent", "Mozilla/5.0"},
            {"accept-language", "en-US"}
          ],
          receive_timeout: receive_timeout
        )

      case resp.status do
        200 -> {:ok, Map.get(resp.body, "products", [])}
        429 -> {:error, :rate_limited}
        status -> {:error, {:http_error, status}}
      end
    rescue
      Req.TransportError -> {:error, :timeout}
    catch
      :exit, _ -> {:error, :timeout}
    end
  end
end
