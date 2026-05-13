defmodule ChatAppWeb.Components.ProductCard do
  use Phoenix.Component
  import Phoenix.HTML

  def format_price(price), do: ChatAppWeb.ProductCard.format_price(price)

  def condition_label(condition), do: ChatAppWeb.ProductCard.condition_label(condition)

  def source_badge_class(source), do: ChatAppWeb.ProductCard.source_label(source)

  defp sanitize_href(href) when is_binary(href) do
    href = String.trim(href)

    cond do
      href == "" -> "#"
      String.starts_with?(href, "/") -> href
      String.starts_with?(href, "//") -> href
      String.starts_with?(href, "http://") -> href
      String.starts_with?(href, "https://") -> href
      true -> "#"
    end
  end

  defp sanitize_href(_), do: "#"

  defp sanitize_img_src(src) when is_binary(src) do
    src = String.trim(src)

    cond do
      src == "" -> "/images/clothing_placeholder.svg"
      String.starts_with?(src, "/") -> src
      String.starts_with?(src, "http://") -> src
      String.starts_with?(src, "https://") -> src
      String.starts_with?(src, "data:image/") -> src
      true -> "/images/clothing_placeholder.svg"
    end
  end

  defp sanitize_img_src(_), do: "/images/clothing_placeholder.svg"

  def render(assigns) when is_map(assigns) do
    item = Map.get(assigns, :item, %{})
    saved = Map.get(assigns, :saved, false)
    reason = Map.get(assigns, :reason, "")

    image_url = Map.get(item, :image_url) || Map.get(item, "image_url")

    img_src =
      if image_url in [nil, ""] do
        "/images/clothing_placeholder.svg"
      else
        image_url
      end

    alt = Map.get(item, :title) || Map.get(item, "title") || ""
    item_id = Map.get(item, :id) || Map.get(item, "id") || ""

    save_text = if saved, do: "Saved", else: "Save"

    title = Phoenix.HTML.safe_to_string(html_escape(alt))
    reason_escaped = Phoenix.HTML.safe_to_string(html_escape(reason))

    source =
      Phoenix.HTML.safe_to_string(
        html_escape(Map.get(item, :source) || Map.get(item, "source") || "")
      )

    url = Map.get(item, :url) || Map.get(item, "url") || ""
    price_val = Map.get(item, :price) || Map.get(item, "price") || Decimal.new("0")
    price_str = format_price(price_val)

    # sanitize URL and image src to avoid javascript: and other unsafe schemes
    safe_url = sanitize_href(url)
    safe_img_src = sanitize_img_src(img_src)

    img_tag =
      "<img src=\"#{safe_img_src}\" alt=\"#{title}\" onerror=\"this.onerror=null;this.src='/images/clothing_placeholder.svg'\" />"

    brand = Map.get(item, :brand) || Map.get(item, "brand") || ""
    size = Map.get(item, :size) || Map.get(item, "size") || ""

    condition =
      condition_label(
        Map.get(item, :condition_normalized) || Map.get(item, "condition_normalized")
      )

    # escape item id for attribute safety
    item_id_escaped = Phoenix.HTML.safe_to_string(html_escape(to_string(item_id)))
    saved_button_text = if saved, do: "Saved", else: ""
    save_button_text = if !saved, do: save_text, else: ""

    iolist = [
      "<div class=\"flex items-start gap-4 rounded-lg border border-foreground/10 bg-background/50 p-3 shadow-sm\">",
      "<div class=\"w-32 h-32 flex-shrink-0 overflow-hidden rounded-md bg-foreground/5\">",
      img_tag,
      "</div>",
      "<div class=\"flex-1 min-w-0\">",
      "<div class=\"flex items-start justify-between gap-3\">",
      "<div class=\"min-w-0\">",
      "<h3 class=\"text-sm font-semibold truncate\">",
      title,
      "</h3>",
      "<p class=\"mt-1 text-xs text-foreground/70 truncate\">",
      price_str,
      " • ",
      source,
      "</p>",
      "</div>",
      "<div class=\"flex-shrink-0 text-right\">",
      "<div class=\"text-xs text-foreground/60\">",
      html_escape(condition) |> Phoenix.HTML.safe_to_string(),
      "</div>",
      "<div class=\"mt-2\">",
      "<button phx-value-item-id=\"",
      item_id_escaped,
      "\" aria-label=\"",
      Phoenix.HTML.safe_to_string(html_escape(save_text <> " " <> title)),
      "\" class=\"px-3 py-1 rounded border border-foreground/10 text-xs bg-background/60\">",
      saved_button_text,
      "</button>",
      "<button phx-value-item-id=\"",
      item_id_escaped,
      "\" aria-label=\"",
      Phoenix.HTML.safe_to_string(html_escape(save_text <> " " <> title)),
      "\" class=\"ml-2 px-3 py-1 rounded bg-accent-interactive text-xs font-semibold text-white\">",
      save_button_text,
      "</button>",
      "</div>",
      "</div>",
      "</div>",
      "<p class=\"mt-2 text-sm text-foreground/70 line-clamp-3\">",
      reason_escaped,
      "</p>",
      "<div class=\"mt-3\"><a href=\"",
      Phoenix.HTML.safe_to_string(html_escape(safe_url)),
      "\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"text-xs text-foreground/70 hover:underline\">View listing</a></div>",
      "</div>",
      "</div>"
    ]

    {:safe, iolist}
  end
end
