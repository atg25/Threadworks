defmodule ChatApp.ETL.Sources.EbayBypassHelper do
  @moduledoc false

  alias ChatApp.ETL.Sources.Ebay.TokenCache

  @doc """
  Standard setup for eBay adapter tests.

  Opens a Bypass server, points :ebay_api_base_url at it, and clears the
  token ETS table. Returns `%{bypass: bypass}` for the test context.
  """
  def setup_bypass(_context \\ %{}) do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")
    TokenCache.clear()
    {:ok, bypass: bypass}
  end

  @doc "Seeds ETS with a valid token that expires two hours from now."
  def seed_valid_token(token \\ "valid_token") do
    TokenCache.put(token, far_future_datetime())
  end

  @doc "Returns a DateTime two hours in the future — used to seed a cache-hit."
  def far_future_datetime do
    DateTime.add(DateTime.utc_now(), 7200, :second)
  end

  @doc "Returns a DateTime one hour in the past — used to seed an expired token."
  def expired_datetime do
    DateTime.add(DateTime.utc_now(), -3600, :second)
  end

  @doc "Reads and returns the eBay search fixture as a JSON-encoded string."
  def ebay_search_fixture do
    File.read!(
      Path.join([File.cwd!(), "test", "support", "http_mocks", "ebay_search_response.json"])
    )
  end

  @doc "Stubs the Bypass server to return 500 if any request arrives."
  def stub_500(bypass) do
    Bypass.stub(bypass, "ANY", "/", fn conn ->
      Plug.Conn.resp(conn, 500, "unexpected request")
    end)
  end

  @doc "Returns a successful token endpoint response handler for Bypass."
  def token_response(token \\ "test_token", expires_in \\ 3600) do
    fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"access_token" => token, "expires_in" => expires_in})
      )
    end
  end
end
