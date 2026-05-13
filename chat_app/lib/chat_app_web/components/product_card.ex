defmodule ChatAppWeb.ProductCard do
  use Phoenix.Component

  @condition_labels %{
    "good" => "Good",
    "like_new" => "Like new",
    "fair" => "Fair",
    "poor" => "Poor",
    "excellent" => "Excellent"
  }

  @source_labels %{
    "ebay" => "eBay",
    "depop" => "Depop",
    "poshmark" => "Poshmark"
  }

  attr :item, :any, required: true
  attr :reason, :string, required: true
  attr :saved, :boolean, required: true

  def product_card(assigns) do
    ~H"""
    <div data-product-card class="product-card">
      <img
        src={if @item.image_url, do: @item.image_url, else: "/images/clothing_placeholder.svg"}
        onerror="this.onerror=null; this.src='/images/clothing_placeholder.svg'"
        alt={@item.title}
        class="product-card-image"
      />
      <div class="product-card-body">
        <p class="product-card-title"><%= @item.title %></p>
        <%= if @item.brand do %>
          <p class="product-card-brand"><%= @item.brand %></p>
        <% end %>
        <p class="product-card-meta">
          <%= @item.size %> · <%= condition_label(@item.condition) %>
        </p>
        <p class="product-card-price">$<%= format_price(@item.price) %></p>
        <span class="product-card-source"><%= source_label(@item.source) %></span>
        <p class="product-card-reason"><em><%= @reason %></em></p>
        <a
          href={@item.url}
          target="_blank"
          rel="noopener noreferrer"
          class="product-card-view-link"
        >View</a>
        <%= if @saved do %>
          <span class="product-card-saved">Saved</span>
        <% else %>
          <button
            type="button"
            phx-click="save_item"
            phx-value-item-id={@item.id}
            class="product-card-save-btn"
          >Save</button>
        <% end %>
      </div>
    </div>
    """
  end

  defp condition_label(condition) do
    Map.get(@condition_labels, to_string(condition), to_string(condition))
  end

  defp source_label(source) do
    Map.get(@source_labels, to_string(source), to_string(source))
  end

  defp format_price(nil), do: "0.00"

  defp format_price(price) do
    price
    |> Decimal.to_string(:normal)
    |> then(fn s ->
      case String.split(s, ".") do
        [int] -> "#{int}.00"
        [int, dec] when byte_size(dec) == 1 -> "#{int}.#{dec}0"
        [int, dec] -> "#{int}.#{String.slice(dec, 0, 2)}"
      end
    end)
  end
end
