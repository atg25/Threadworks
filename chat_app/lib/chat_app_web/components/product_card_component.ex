defmodule ChatAppWeb.ProductCard do
  @moduledoc "HEEx function component and helpers for product cards."
  use Phoenix.Component

  @condition_labels %{
    new: "New",
    used: "Used",
    refurbished: "Refurbished",
    unknown: "Unknown"
  }

  @source_labels %{
    "amazon" => "Amazon",
    "ebay" => "eBay",
    "depop" => "Depop",
    "poshmark" => "Poshmark",
    "store" => "Store"
  }

  def product_card(assigns) do
    assigns =
      assigns
      |> assign_new(:item, fn -> nil end)
      |> assign_new(:reason, fn -> "" end)
      |> assign_new(:saved, fn -> false end)
      |> assign(:safe_url, safe_href(assigns[:item]))

    ~H"""
    <div class="flex items-start gap-4 rounded-lg border border-foreground/10 bg-background/50 p-3 shadow-sm" data-product-card>
      <div class="w-32 h-32 flex-shrink-0 overflow-hidden rounded-md bg-foreground/5">
        <img
          src={@item.image_url || "/images/clothing_placeholder.svg"}
          alt={@item.title || "product image"}
          class="object-cover w-full h-full"
          onerror="this.onerror=null;this.src='/images/clothing_placeholder.svg'"
        />
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h3 class="text-sm font-semibold truncate">{@item.title}</h3>
            <p class="mt-1 text-xs text-foreground/70 truncate">{format_price(@item.price)} • <span class="capitalize">{source_label(@item.source)}</span></p>
          </div>

          <div class="flex-shrink-0 text-right">
            <div class="text-xs text-foreground/60">{condition_label(@item.condition_normalized || @item.condition)}</div>
            <div class="mt-2">
              <button
                :if={@saved}
                phx-click="unsave_item"
                phx-value-item-id={@item.id}
                aria-label={"Unsave " <> (@item.title || "item")}
                class="px-3 py-1 rounded border border-foreground/10 text-xs bg-background/60"
              >
                Saved
              </button>

              <button
                :if={!@saved}
                phx-click="save_item"
                phx-value-item-id={@item.id}
                aria-label={"Save " <> (@item.title || "item")}
                class="ml-2 px-3 py-1 rounded bg-accent-interactive text-xs font-semibold text-white"
              >
                Save
              </button>
            </div>
          </div>
        </div>

        <p class="mt-2 text-sm text-foreground/70 line-clamp-3">{@reason}</p>

        <div class="mt-3 flex items-center gap-3">
          <a href={@safe_url} target="_blank" rel="noopener noreferrer" class="text-xs text-foreground/70 hover:underline">View listing</a>
        </div>
      </div>
    </div>
    """
  end

  def condition_label(nil), do: @condition_labels[:unknown]

  def condition_label(cond) when is_binary(cond) do
    key = String.to_existing_atom(cond)
    Map.get(@condition_labels, key, String.capitalize(String.replace(cond, "_", " ")))
  rescue
    ArgumentError -> String.capitalize(String.replace(cond, "_", " "))
  end

  def condition_label(cond) when is_atom(cond) do
    Map.get(@condition_labels, cond, String.capitalize(String.replace(to_string(cond), "_", " ")))
  end

  defp safe_href(nil), do: "#"

  defp safe_href(item) do
    url = Map.get(item, :url) || ""
    url = String.trim(url)

    cond do
      url == "" -> "#"
      String.starts_with?(url, "/") -> url
      String.starts_with?(url, "http://") -> url
      String.starts_with?(url, "https://") -> url
      true -> "#"
    end
  end

  def source_label(nil), do: ""
  def source_label(src) when is_binary(src), do: Map.get(@source_labels, src, src)

  def format_price(nil), do: ""

  def format_price(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end

  def format_price(n) when is_integer(n) do
    format_price(Decimal.new(n) |> Decimal.div(1))
  end

  def format_price(n) when is_float(n) do
    n
    |> Decimal.from_float()
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
    |> then(&"$#{&1}")
  end
end
