defmodule ChatApp.ETL.Sources.DepopTest do
  use ExUnit.Case, async: false

  alias ChatApp.ETL.Sources.Depop

  @search_path "/api/v3/search"

  defp depop_search_fixture do
    Path.join([File.cwd!(), "test", "support", "http_mocks", "depop_search_response.json"])
    |> File.read!()
  end

  setup do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  # ---------------------------------------------------------------------------
  # Test 1 — item count from fixture
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns one raw map per product in fixture", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, depop_search_fixture())
    end)

    {:ok, items} = Depop.fetch_items("vintage levi")
    assert length(items) == 24
    assert Enum.all?(items, &is_map/1)
  end

  # ---------------------------------------------------------------------------
  # Test 2 — required keys present, string-keyed
  # ---------------------------------------------------------------------------

  test "fetch_items/1 raw maps preserve all required Depop keys", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, depop_search_fixture())
    end)

    {:ok, items} = Depop.fetch_items("vintage levi")
    first = hd(items)

    for key <- ~w[id description displayedPrice brand sizes pictureUrl slug] do
      assert Map.has_key?(first, key), "expected key #{inspect(key)} in #{inspect(first)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Test 3 — User-Agent header
  # ---------------------------------------------------------------------------

  test "fetch_items/1 sends User-Agent: Mozilla/5.0 header", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      send(parent, {:headers, conn.req_headers})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => []}))
    end)

    Depop.fetch_items("test")

    assert_received {:headers, headers}
    assert {"user-agent", "Mozilla/5.0"} in headers
  end

  # ---------------------------------------------------------------------------
  # Test 4 — Accept-Language header
  # ---------------------------------------------------------------------------

  test "fetch_items/1 sends Accept-Language: en-US header", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      send(parent, {:headers, conn.req_headers})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => []}))
    end)

    Depop.fetch_items("test")

    assert_received {:headers, headers}
    assert {"accept-language", "en-US"} in headers
  end

  # ---------------------------------------------------------------------------
  # Test 5 — query string params
  # ---------------------------------------------------------------------------

  test "fetch_items/1 builds URL with q and limit=24 query params", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      send(parent, {:query, conn.query_string})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => []}))
    end)

    Depop.fetch_items("vintage levi")

    assert_received {:query, query}

    assert String.contains?(query, "q=vintage+levi") or
             String.contains?(query, "q=vintage%20levi")

    assert String.contains?(query, "limit=24")
  end

  # ---------------------------------------------------------------------------
  # Test 6 — empty products list
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns {:ok, []} when products list is empty", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => []}))
    end)

    assert Depop.fetch_items("nothing") == {:ok, []}
  end

  # ---------------------------------------------------------------------------
  # Test 7 — 429 rate limit
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns {:error, :rate_limited} on 429", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      Plug.Conn.resp(conn, 429, "")
    end)

    assert Depop.fetch_items("test") == {:error, :rate_limited}
  end

  # ---------------------------------------------------------------------------
  # Test 8 — network timeout
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns {:error, :timeout} on network timeout", %{bypass: _bypass} do
    {:ok, listen_sock} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen_sock)

    Task.start(fn ->
      case :gen_tcp.accept(listen_sock, 5_000) do
        {:ok, _} -> :timer.sleep(30_000)
        _ -> :ok
      end
    end)

    Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{port}")

    assert Depop.fetch_items("timeout", receive_timeout: 100) == {:error, :timeout}

    :gen_tcp.close(listen_sock)
  end

  # ---------------------------------------------------------------------------
  # Test 9 — sizes: [] passes through
  # ---------------------------------------------------------------------------

  test "fetch_items/1 passes through sizes: [] without crash", %{bypass: bypass} do
    item = %{
      "id" => "dp008",
      "description" => "test",
      "displayedPrice" => 18.0,
      "brand" => "Stussy",
      "sizes" => [],
      "pictureUrl" => "https://example.com/p.jpg",
      "slug" => "dp008-test"
    }

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => [item]}))
    end)

    {:ok, [result]} = Depop.fetch_items("test")
    assert result["sizes"] == []
  end

  # ---------------------------------------------------------------------------
  # Test 10 — sizes: null passes through
  # ---------------------------------------------------------------------------

  test "fetch_items/1 passes through sizes: null without crash", %{bypass: bypass} do
    item = %{
      "id" => "dp_null",
      "description" => "test",
      "displayedPrice" => 10.0,
      "brand" => "X",
      "sizes" => nil,
      "pictureUrl" => "https://example.com/p.jpg",
      "slug" => "dp-null-test"
    }

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => [item]}))
    end)

    {:ok, [result]} = Depop.fetch_items("test")
    assert result["sizes"] == nil
  end

  # ---------------------------------------------------------------------------
  # Test 11 — pictureUrl: null passes through
  # ---------------------------------------------------------------------------

  test "fetch_items/1 passes through nil pictureUrl without crash", %{bypass: bypass} do
    item = %{
      "id" => "dp005",
      "description" => "test",
      "displayedPrice" => 22.0,
      "brand" => "Ralph Lauren",
      "sizes" => ["M"],
      "pictureUrl" => nil,
      "slug" => "dp005-test"
    }

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => [item]}))
    end)

    {:ok, [result]} = Depop.fetch_items("test")
    assert result["pictureUrl"] == nil
  end

  # ---------------------------------------------------------------------------
  # Test 12 — non-numeric displayedPrice passes through
  # ---------------------------------------------------------------------------

  test "fetch_items/1 passes through non-numeric displayedPrice without crash", %{bypass: bypass} do
    item = %{
      "id" => "dp_uk",
      "description" => "UK item",
      "displayedPrice" => "£12.00",
      "brand" => "Topman",
      "sizes" => ["M"],
      "pictureUrl" => "https://example.com/p.jpg",
      "slug" => "dp-uk-item"
    }

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => [item]}))
    end)

    {:ok, [result]} = Depop.fetch_items("test")
    assert result["displayedPrice"] == "£12.00"
  end

  # ---------------------------------------------------------------------------
  # Test 13 — respects :depop_api_base_url config
  # ---------------------------------------------------------------------------

  test "fetch_items/1 uses :depop_api_base_url from application config", %{bypass: bypass} do
    Application.put_env(:chat_app, :depop_api_base_url, "http://localhost:#{bypass.port}")

    Bypass.expect_once(bypass, "GET", @search_path, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{"products" => []}))
    end)

    Depop.fetch_items("config test")
  end
end
