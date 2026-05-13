defmodule ChatApp.ETL.Sources.EbayTest do
  use ExUnit.Case, async: false

  alias ChatApp.ETL.Sources.Ebay
  alias ChatApp.ETL.Sources.Ebay.TokenCache

  @token_path "/identity/v1/oauth2/token"
  @search_path "/buy/browse/v1/item_summary/search"

  defp far_future_datetime, do: DateTime.add(DateTime.utc_now(), 7200, :second)
  defp expired_datetime, do: DateTime.add(DateTime.utc_now(), -3600, :second)

  defp seed_valid_token(token \\ "valid_token") do
    TokenCache.put(token, far_future_datetime())
  end

  defp ebay_search_fixture do
    Path.join([File.cwd!(), "test", "support", "http_mocks", "ebay_search_response.json"])
    |> File.read!()
  end

  defp token_resp(bypass, token, expires_in) do
    Bypass.expect_once(bypass, "POST", @token_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"access_token" => token, "expires_in" => expires_in})
      )
    end)
  end

  setup do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")
    Application.put_env(:chat_app, :ebay_app_id, "test_app_id")
    Application.put_env(:chat_app, :ebay_cert_id, "test_cert_id")
    TokenCache.clear()
    {:ok, bypass: bypass}
  end

  # ---------------------------------------------------------------------------
  # Unit tests — token cache (Tests 1–5)
  # ---------------------------------------------------------------------------

  test "get_token/0 returns cached token without HTTP when cache valid", %{bypass: bypass} do
    TokenCache.put("cached_token", far_future_datetime())

    Bypass.stub(bypass, "POST", @token_path, fn conn ->
      Plug.Conn.resp(conn, 500, "should not be called")
    end)

    assert Ebay.get_token() == "cached_token"
  end

  test "get_token/0 refreshes expired token and updates cache", %{bypass: bypass} do
    TokenCache.put("old_token", expired_datetime())
    token_resp(bypass, "new_token", 7200)

    assert Ebay.get_token() == "new_token"
    {cached_token, expires_at} = TokenCache.get()
    assert cached_token == "new_token"
    assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  test "get_token/0 fetches token when cache is empty", %{bypass: bypass} do
    token_resp(bypass, "fresh_token", 3600)

    assert Ebay.get_token() == "fresh_token"
  end

  test "get_token/0 fires exactly one HTTP call under 10 concurrent callers", %{bypass: bypass} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Bypass.stub(bypass, "POST", @token_path, fn conn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(30)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(
        200,
        Jason.encode!(%{"access_token" => "concurrent_token", "expires_in" => 3600})
      )
    end)

    results =
      Enum.map(1..10, fn _ -> Task.async(fn -> Ebay.get_token() end) end)
      |> Task.await_many(5000)

    assert Agent.get(counter, & &1) == 1
    assert Enum.all?(results, &(&1 == "concurrent_token"))
    Agent.stop(counter)
  end

  test "get_token/0 returns {:error, :missing_credentials} when app_id is empty string",
       %{bypass: bypass} do
    Application.put_env(:chat_app, :ebay_app_id, "")

    Bypass.stub(bypass, "POST", @token_path, fn conn ->
      Plug.Conn.resp(conn, 500, "should not be called")
    end)

    assert Ebay.get_token() == {:error, :missing_credentials}
  end

  # ---------------------------------------------------------------------------
  # Integration tests — HTTP search (Tests 6–13)
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns 50 raw maps preserving eBay nested JSON structure",
       %{bypass: bypass} do
    seed_valid_token()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ebay_search_fixture())
    end)

    {:ok, items} = Ebay.fetch_items("vintage levi")
    assert length(items) == 50

    first = hd(items)
    assert Map.has_key?(first, "itemId")
    assert Map.has_key?(first, "title")
    assert is_map(first["price"])
    assert is_map(first["image"])
    assert Map.has_key?(first, "itemWebUrl")
  end

  test "fetch_items/1 sends correct query string parameters", %{bypass: bypass} do
    seed_valid_token()
    parent = self()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      send(parent, {:query, conn.query_string})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"itemSummaries" => []}))
    end)

    Ebay.fetch_items("vintage levi")

    assert_received {:query, query}

    assert String.contains?(query, "q=vintage+levi") or
             String.contains?(query, "q=vintage%20levi")

    assert String.contains?(query, "category_ids=15724")
    assert String.contains?(query, "11450")
    assert String.contains?(query, "limit=50")
  end

  test "fetch_items/1 sends Bearer token in Authorization header", %{bypass: bypass} do
    TokenCache.put("test_bearer_token", far_future_datetime())
    parent = self()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      auth = Enum.find(conn.req_headers, fn {k, _} -> k == "authorization" end)
      send(parent, {:auth, auth})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"itemSummaries" => []}))
    end)

    Ebay.fetch_items("test query")

    assert_received {:auth, {"authorization", auth_value}}
    assert auth_value == "Bearer test_bearer_token"
  end

  test "fetch_items/1 returns {:error, :unauthorized} on 401", %{bypass: bypass} do
    seed_valid_token()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(401, Jason.encode!(%{"error" => "Invalid token"}))
    end)

    assert Ebay.fetch_items("test") == {:error, :unauthorized}
  end

  test "fetch_items/1 returns {:ok, []} when itemSummaries is empty list", %{bypass: bypass} do
    seed_valid_token()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"total" => 0, "itemSummaries" => []}))
    end)

    assert Ebay.fetch_items("empty") == {:ok, []}
  end

  test "fetch_items/1 returns {:ok, []} when itemSummaries key is absent", %{bypass: bypass} do
    seed_valid_token()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"total" => 0}))
    end)

    assert Ebay.fetch_items("absent key") == {:ok, []}
  end

  test "fetch_items/1 returns {:error, :timeout} on network timeout", %{bypass: _} do
    seed_valid_token()

    # Use a raw TCP socket that accepts the connection but never sends a response.
    # This produces a genuine receive_timeout without involving a Bypass/Cowboy handler,
    # which avoids the PSPDFKit Bypass fork treating the client disconnect as a
    # verification failure (it stores {:exit, :shutdown} in results and re-raises it).
    {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_sock)

    # Accept in background but never respond — intentionally unlinked.
    Task.start(fn ->
      case :gen_tcp.accept(listen_sock, 5_000) do
        {:ok, _} -> :timer.sleep(30_000)
        _ -> :ok
      end
    end)

    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{port}")

    assert Ebay.fetch_items("timeout", receive_timeout: 100) == {:error, :timeout}

    :gen_tcp.close(listen_sock)
  end

  test "fetch_items/1 uses :ebay_api_base_url from application config", %{bypass: bypass} do
    seed_valid_token()
    Application.put_env(:chat_app, :ebay_api_base_url, "http://localhost:#{bypass.port}")

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"itemSummaries" => []}))
    end)

    Ebay.fetch_items("config test")
  end

  # ---------------------------------------------------------------------------
  # Integration tests — OAuth token request format (Tests 14–15)
  # ---------------------------------------------------------------------------

  test "token refresh sends client_credentials grant with form-encoded body", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "POST", @token_path, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:body, body})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"access_token" => "token", "expires_in" => 3600}))
    end)

    Ebay.get_token()

    assert_received {:body, body}
    assert String.contains?(body, "grant_type=client_credentials")
    assert String.contains?(body, "scope=")
    assert String.contains?(body, "api_scope")
  end

  test "token refresh sends Basic auth with base64(app_id:cert_id)", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "POST", @token_path, fn conn ->
      auth = Enum.find(conn.req_headers, fn {k, _} -> k == "authorization" end)
      send(parent, {:auth, auth})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"access_token" => "token", "expires_in" => 3600}))
    end)

    Ebay.get_token()

    expected_auth = "Basic " <> Base.encode64("test_app_id:test_cert_id")
    assert_received {:auth, {"authorization", ^expected_auth}}
  end
end
