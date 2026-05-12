defmodule ChatApp.ETL.Sources.Poshmark do
  # CSS selectors are hardcoded; HTML drift will break parsing silently
  # unless the selector regression test (test 12) is maintained.

  @search_path "/search"

  @doc false
  def parse_html(html, base_url \\ nil) when is_binary(html) do
    base_url = base_url || Application.get_env(:chat_app, :poshmark_base_url)
    doc = Floki.parse_document!(html)

    items =
      Floki.find(doc, "[data-id]")
      |> Enum.map(fn el ->
        source_id = Floki.attribute(el, "data-id") |> List.first()

        title =
          Floki.find(el, ".listing__title")
          |> List.first()
          |> then(fn e -> if e, do: Floki.text(e) |> String.trim(), else: nil end)

        price =
          Floki.find(el, ".listing__ipad-price")
          |> List.first()
          |> then(fn e -> if e, do: Floki.text(e) |> String.trim(), else: nil end)

        brand =
          Floki.find(el, ".listing__brand")
          |> List.first()
          |> then(fn e -> if e, do: Floki.text(e) |> String.trim(), else: nil end)

        size =
          Floki.find(el, ".listing__size")
          |> List.first()
          |> then(fn e -> if e, do: Floki.text(e) |> String.trim(), else: nil end)

        condition =
          Floki.find(el, ".listing__condition")
          |> List.first()
          |> then(fn e -> if e, do: Floki.text(e) |> String.trim(), else: nil end)

        image_url =
          Floki.find(el, "img")
          |> List.first()
          |> then(fn e ->
            if e, do: Floki.attribute(e, "src") |> List.first(), else: nil
          end)

        href =
          Floki.find(el, "a")
          |> List.first()
          |> then(fn e ->
            if e, do: Floki.attribute(e, "href") |> List.first(), else: nil
          end)

        url =
          cond do
            is_nil(href) -> nil
            String.starts_with?(href, "http") -> href
            is_nil(base_url) -> nil
            true -> base_url <> href
          end

        %{
          "source_id" => source_id,
          "title" => title,
          "price" => price,
          "brand" => brand,
          "size" => size,
          "image_url" => image_url,
          "url" => url,
          "condition" => condition
        }
      end)

    {:ok, items}
  end

  def fetch_items(query, opts \\ []) do
    base_url = Application.get_env(:chat_app, :poshmark_base_url)
    receive_timeout = Keyword.get(opts, :receive_timeout, 5_000)

    try do
      resp =
        Req.get!("#{base_url}#{@search_path}",
          retry: false,
          params: [query: query, type: "listings", src: "dir"],
          receive_timeout: receive_timeout
        )

      case resp.status do
        200 -> parse_html(resp.body, base_url)
        _ -> {:ok, []}
      end
    rescue
      Req.TransportError -> {:error, :timeout}
    catch
      :exit, _ -> {:error, :timeout}
    end
  end
end
