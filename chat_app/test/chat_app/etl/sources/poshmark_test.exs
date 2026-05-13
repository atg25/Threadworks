defmodule ChatApp.ETL.Sources.PoshmarkTest do
  use ExUnit.Case, async: false

  alias ChatApp.ETL.Sources.Poshmark

  @fixture File.read!("test/support/http_mocks/poshmark_search.html")

  setup do
    bypass = Bypass.open()
    Application.put_env(:chat_app, :poshmark_base_url, "http://localhost:#{bypass.port}")
    {:ok, bypass: bypass}
  end

  # ---------------------------------------------------------------------------
  # Test 1 — item count matches data-id elements in fixture
  # ---------------------------------------------------------------------------

  test "parse_html/1 returns one map per listing with data-id" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    {:ok, doc} = Floki.parse_document(@fixture)
    expected_count = Floki.find(doc, "[data-id]") |> length()
    assert length(items) == expected_count
    assert expected_count > 0
  end

  # ---------------------------------------------------------------------------
  # Test 2 — source_id extracted from data-id attribute
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts source_id from data-id attribute" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    first = hd(items)
    assert is_binary(first["source_id"])
    assert String.trim(first["source_id"]) != ""
    # fixture first listing has data-id="pm001"
    assert first["source_id"] == "pm001"
  end

  # ---------------------------------------------------------------------------
  # Test 3 — title extracted from .listing__title
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts title from .listing__title" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    first = hd(items)
    assert is_binary(first["title"])
    assert String.trim(first["title"]) != ""
  end

  # ---------------------------------------------------------------------------
  # Test 4 — price extracted from .listing__ipad-price
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts price from .listing__ipad-price" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    first = hd(items)
    assert is_binary(first["price"])
    assert String.trim(first["price"]) != ""
  end

  # ---------------------------------------------------------------------------
  # Test 5 — brand extracted from .listing__brand
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts brand from .listing__brand" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    first = hd(items)
    assert is_binary(first["brand"])
    assert String.trim(first["brand"]) != ""
  end

  # ---------------------------------------------------------------------------
  # Test 6 — size extracted from .listing__size (first item that has one)
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts size from .listing__size" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    # fixture item pm001 has size "30"
    first = hd(items)
    assert is_binary(first["size"])
    assert String.trim(first["size"]) != ""
  end

  # ---------------------------------------------------------------------------
  # Test 7 — image_url extracted from img[src], must be absolute https://
  # ---------------------------------------------------------------------------

  test "parse_html/1 extracts image_url from img[src]" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    first = hd(items)
    assert is_binary(first["image_url"])
    assert String.starts_with?(first["image_url"], "https://")
  end

  # ---------------------------------------------------------------------------
  # Test 8 — url is built as absolute from relative a[href]
  # ---------------------------------------------------------------------------

  test "parse_html/1 builds absolute URL from a[href]" do
    {:ok, items} = Poshmark.parse_html(@fixture)
    # fixture pm001 href is /listing/Levis-501-Jeans-pm001
    first = hd(items)
    base_url = Application.get_env(:chat_app, :poshmark_base_url)
    assert first["url"] == base_url <> "/listing/Levis-501-Jeans-pm001"
  end

  # ---------------------------------------------------------------------------
  # Test 9 — size: nil when .listing__size element is absent
  # ---------------------------------------------------------------------------

  test "parse_html/1 returns size: nil when .listing__size absent" do
    html = """
    <html><body>
    <div class="listing" data-id="test001">
      <a href="/listing/test001"><img src="https://example.com/img.jpg" alt="Test"></a>
      <span class="listing__title">Test Item</span>
      <span class="listing__ipad-price">$10</span>
      <span class="listing__brand">TestBrand</span>
    </div>
    </body></html>
    """

    {:ok, [item]} = Poshmark.parse_html(html)
    assert item["size"] == nil
  end

  # ---------------------------------------------------------------------------
  # Test 10 — image_url: nil when img[src] is absent
  # ---------------------------------------------------------------------------

  test "parse_html/1 returns image_url: nil when img[src] absent" do
    html = """
    <html><body>
    <div class="listing" data-id="test002">
      <a href="/listing/test002">No image here</a>
      <span class="listing__title">Test Item No Image</span>
      <span class="listing__ipad-price">$20</span>
      <span class="listing__brand">TestBrand</span>
    </div>
    </body></html>
    """

    {:ok, [item]} = Poshmark.parse_html(html)
    assert item["image_url"] == nil
  end

  # ---------------------------------------------------------------------------
  # Test 11 — returns {:ok, []} when no listing elements in HTML
  # ---------------------------------------------------------------------------

  test "parse_html/1 returns {:ok, []} on HTML with no listing elements" do
    assert Poshmark.parse_html("<html><body><p>No results</p></body></html>") == {:ok, []}
  end

  # ---------------------------------------------------------------------------
  # Test 12 — selector regression: all 5 CSS selectors match fixture
  # ---------------------------------------------------------------------------

  test "All 5 CSS selectors return at least one match in fixture HTML" do
    {:ok, doc} = Floki.parse_document(@fixture)

    selectors = [
      {"[data-id]", "data-id attribute selector"},
      {".listing__title", ".listing__title class selector"},
      {".listing__ipad-price", ".listing__ipad-price class selector"},
      {".listing__brand", ".listing__brand class selector"},
      {".listing__size", ".listing__size class selector"}
    ]

    for {selector, description} <- selectors do
      matches = Floki.find(doc, selector)

      assert length(matches) > 0,
             "Selector regression: #{description} returned no matches — fixture HTML may have drifted"
    end
  end

  # ---------------------------------------------------------------------------
  # Test 13 — fetch_items/1 sends GET to /search with correct query params
  # ---------------------------------------------------------------------------

  test "fetch_items/1 sends GET to Poshmark search URL with query params", %{bypass: bypass} do
    parent = self()

    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      send(parent, {:conn, conn})

      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.resp(200, "<html><body></body></html>")
    end)

    Poshmark.fetch_items("vintage levi")

    assert_received {:conn, conn}

    assert String.contains?(conn.query_string, "query=vintage+levi") or
             String.contains?(conn.query_string, "query=vintage%20levi")

    assert String.contains?(conn.query_string, "type=listings")
    assert String.contains?(conn.query_string, "src=dir")
  end

  # ---------------------------------------------------------------------------
  # Test 14 — fetch_items/1 parses Bypass-served fixture HTML and returns items
  # ---------------------------------------------------------------------------

  test "fetch_items/1 parses Bypass-served HTML and returns items", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.resp(200, @fixture)
    end)

    {:ok, items} = Poshmark.fetch_items("vintage levi")
    assert length(items) > 0
    assert Enum.all?(items, &is_map/1)
  end

  # ---------------------------------------------------------------------------
  # Test 15 — fetch_items/1 returns {:error, :timeout} on network timeout
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

    Application.put_env(:chat_app, :poshmark_base_url, "http://localhost:#{port}")

    assert Poshmark.fetch_items("timeout", receive_timeout: 100) == {:error, :timeout}

    :gen_tcp.close(listen_sock)
  end

  # ---------------------------------------------------------------------------
  # Test 16 — fetch_items/1 returns {:ok, []} on non-200 response
  # ---------------------------------------------------------------------------

  test "fetch_items/1 returns {:ok, []} on non-200 response", %{bypass: bypass} do
    Bypass.expect_once(bypass, "GET", "/search", fn conn ->
      Plug.Conn.resp(conn, 503, "Service Unavailable")
    end)

    assert Poshmark.fetch_items("test") == {:ok, []}
  end
end
