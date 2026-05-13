defmodule ChatAppWeb.Live.SavedLive do
  use ChatAppWeb, :live_view

  import Ecto.Query

  alias ChatApp.Clothing
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo
  alias ChatAppWeb.Components.ProductCard

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:id)])

    all_saved_items =
      if is_integer(user_id) do
        Clothing.list_saved_items(user_id)
      else
        []
      end

    saved_items = apply_sort(all_saved_items, "Recently saved")

    {:ok,
     socket
     |> assign(:all_saved_items, all_saved_items)
     |> assign(:saved_items, saved_items)
     |> assign(:filter_source, "All")
     |> assign(:sort_by, "Recently saved")}
  end

  @impl true
  def handle_event("filter", %{"filter_source" => source}, socket) do
    saved_items =
      socket.assigns.all_saved_items
      |> apply_filter(source)
      |> apply_sort(socket.assigns.sort_by)

    {:noreply, assign(socket, saved_items: saved_items, filter_source: source)}
  end

  @impl true
  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    saved_items =
      socket.assigns.all_saved_items
      |> apply_filter(socket.assigns.filter_source)
      |> apply_sort(sort_by)

    {:noreply, assign(socket, saved_items: saved_items, sort_by: sort_by)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl p-4 space-y-4">
        <div class="flex items-end justify-between gap-4">
          <.header>
            <p>Saved</p>
            <:subtitle>Saved items for your account.</:subtitle>
          </.header>

          <form phx-change="filter" class="flex items-center gap-2">
            <label class="text-sm font-semibold" for="filter_source">Source</label>
            <select id="filter_source" name="filter_source" class="input">
              <option selected={@filter_source == "All"}>All</option>
              <option selected={@filter_source == "Depop"}>Depop</option>
              <option selected={@filter_source == "eBay"}>eBay</option>
              <option selected={@filter_source == "Poshmark"}>Poshmark</option>
            </select>
          </form>

          <form phx-change="sort" class="flex items-center gap-2">
            <label class="text-sm font-semibold" for="sort_by">Sort</label>
            <select id="sort_by" name="sort_by" class="input">
              <option selected={@sort_by == "Recently saved"}>Recently saved</option>
              <option selected={@sort_by == "Price: low to high"}>Price: low to high</option>
              <option selected={@sort_by == "Price: high to low"}>Price: high to low</option>
            </select>
          </form>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%= for saved_item <- @saved_items do %>
            {render_saved_card(saved_item)}
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Unit-tested helpers

  def format_price_delta_badge(:no_history) do
    {:safe, "<span class=\"badge badge-muted\">No price history</span>"}
  end

  def format_price_delta_badge(%{saved_price: saved_price, current_price: current_price}) do
    pct =
      current_price
      |> Decimal.sub(saved_price)
      |> Decimal.div(saved_price)
      |> Decimal.mult(Decimal.new("100"))
      # Match sprint spec expectation: 45.00 -> 38.00 renders "↓15%" (truncate toward zero).
      |> Decimal.round(0, :down)

    {arrow, magnitude, class} =
      cond do
        Decimal.compare(pct, 0) == :lt -> {"↓", Decimal.abs(pct), "badge-green green"}
        Decimal.compare(pct, 0) == :gt -> {"↑", pct, "badge-red red"}
        true -> {"→", pct, "badge-muted"}
      end

    pct_str = Decimal.to_string(magnitude, :normal)

    {:safe,
     [
       "<span class=\"badge ",
       class,
       "\" aria-label=\"Price delta\">",
       arrow,
       pct_str,
       "%</span>"
     ]}
  end

  def render_saved_card(%{item: nil}) do
    {:safe,
     [
       "<div class=\"relative border rounded p-4\">",
       "<div class=\"absolute inset-0 bg-black/10 flex items-center justify-center\">",
       "<div class=\"font-semibold\">Listing Removed</div>",
       "</div>",
       "</div>"
     ]}
  end

  def render_saved_card(saved_item) do
    item = saved_item.item
    delta = price_delta_for_item(item.id)
    current_price = current_price_for_item(item.id)

    assigns = %{
      item: item,
      delta: delta,
      current_price: current_price
    }

    ~H"""
    <div class="space-y-2">
      <div class="flex items-center justify-between gap-2">
        {format_price_delta_badge(@delta)}
        <%= if is_struct(@current_price, Decimal) do %>
          <div class="text-sm font-semibold">Now {ProductCard.format_price(@current_price)}</div>
        <% end %>
      </div>

      {ProductCard.render(%{item: @item, saved: true, reason: ""})}
    </div>
    """
  end

  defp apply_filter(saved_items, "All"), do: saved_items

  defp apply_filter(saved_items, source_label) do
    wanted = normalize_source_label(source_label)

    Enum.filter(saved_items, fn s ->
      item_source =
        (s.item && (s.item.source || "")) ||
          ""

      normalize_source_label(item_source) == wanted
    end)
  end

  defp normalize_source_label("depop"), do: "depop"
  defp normalize_source_label("Depop"), do: "depop"
  defp normalize_source_label("ebay"), do: "ebay"
  defp normalize_source_label("eBay"), do: "ebay"
  defp normalize_source_label("poshmark"), do: "poshmark"
  defp normalize_source_label("Poshmark"), do: "poshmark"
  defp normalize_source_label(other) when is_binary(other), do: String.downcase(other)
  defp normalize_source_label(_), do: ""

  defp apply_sort(saved_items, "Recently saved") do
    Enum.sort(saved_items, fn left, right ->
      compare_recently_saved(left, right) != :gt
    end)
  end

  defp apply_sort(saved_items, "Price: low to high") do
    Enum.sort(saved_items, fn left, right ->
      Decimal.compare(price_sort_value(left), price_sort_value(right)) != :gt
    end)
  end

  defp apply_sort(saved_items, "Price: high to low") do
    Enum.sort(saved_items, fn left, right ->
      Decimal.compare(price_sort_value(left), price_sort_value(right)) != :lt
    end)
  end

  defp apply_sort(saved_items, _), do: saved_items

  defp price_sort_value(%{item: %{price: price}}) when is_struct(price, Decimal), do: price
  defp price_sort_value(%{item: %{price: price}}) when is_binary(price), do: Decimal.new(price)
  defp price_sort_value(_), do: Decimal.new("0")

  defp compare_recently_saved(left, right) do
    left_key = {left.inserted_at || ~U[1970-01-01 00:00:00Z], left.id || 0}
    right_key = {right.inserted_at || ~U[1970-01-01 00:00:00Z], right.id || 0}

    cond do
      left_key > right_key -> :gt
      left_key < right_key -> :lt
      true -> :eq
    end
  end

  defp price_delta_for_item(item_id) when is_integer(item_id) do
    case two_most_recent_prices(item_id) do
      [latest, previous] ->
        %{saved_price: previous.price, current_price: latest.price}

      _ ->
        :no_history
    end
  end

  defp current_price_for_item(item_id) when is_integer(item_id) do
    Repo.one(
      from(ph in PriceHistory,
        where: ph.item_id == ^item_id,
        order_by: [desc: ph.inserted_at, desc: ph.id],
        limit: 1,
        select: ph.price
      )
    )
  end

  defp two_most_recent_prices(item_id) do
    Repo.all(
      from(ph in PriceHistory,
        where: ph.item_id == ^item_id,
        order_by: [desc: ph.inserted_at, desc: ph.id],
        limit: 2
      )
    )
  end
end
