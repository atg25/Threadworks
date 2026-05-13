defmodule ChatApp.Demo do
  @moduledoc false

  import Ecto.Query

  alias ChatApp.Accounts
  alias ChatApp.Accounts.User
  alias ChatApp.Clothing
  alias ChatApp.Clothing.Item
  alias ChatApp.Clothing.PriceHistory
  alias ChatApp.Repo
  alias ChatApp.Search.FTS5Index
  alias ChatApp.Search.VectorStore

  @email "demo@threadworks.local"
  @source_id_prefix "demo:"

  @items [
    %{
      source_id: "demo:vintage-levi-jeans-01",
      title: "Levi's Jeans 505 Mens 40x30 Straight Cut 90s Blue Denim USA 505",
      brand: "Levi's",
      size: "40",
      condition: "used",
      price: "23.99",
      source: "ebay",
      image_url: "/images/demo/levis.png",
      url: "https://www.ebay.com/itm/287237415699",
      description:
        "Vintage Levi's 505 straight cut jeans in classic blue denim. Size 40x30. Pre-owned in good condition with authentic 90s fading and patina. Perfect for vintage streetwear styling, casual outfits, or as a foundation piece. Last one available."
    },
    %{
      source_id: "demo:denim-jacket-01",
      title: "Vintage Levi's Denim Trucker Jacket - Streetwear Blue",
      brand: "Levi's",
      size: "M",
      condition: "used",
      price: "78.00",
      source: "ebay",
      image_url: "https://picsum.photos/id/1011/800/600",
      url: "https://example.com/demo/denim-jacket",
      description:
        "Vintage blue denim jacket with relaxed streetwear fit, worn-in wash, and sturdy cotton texture."
    },
    %{
      source_id: "demo:denim-jacket-02",
      title: "Faded 90s Denim Chore Jacket Under 100",
      brand: "Gap",
      size: "S",
      condition: "used",
      price: "64.00",
      source: "depop",
      image_url: "https://picsum.photos/id/1025/800/600",
      url: "https://example.com/demo/denim-chore",
      description:
        "Lightweight faded denim layer for vintage streetwear outfits, easy over tees and hoodies."
    },
    %{
      source_id: "demo:street-sneaker-01",
      title: "Nike Retro Court Sneakers for Streetwear",
      brand: "Nike",
      size: "8",
      condition: "used",
      price: "58.00",
      source: "poshmark",
      image_url: "https://picsum.photos/id/102/800/600",
      url: "https://example.com/demo/nike-court",
      description:
        "Clean retro sneakers with a low profile, works with denim, cargos, and streetwear."
    },
    %{
      source_id: "demo:minimal-dress-01",
      title: "Reformation Minimal Black Slip Dress for Dinner",
      brand: "Reformation",
      size: "S",
      condition: "used",
      price: "118.00",
      source: "depop",
      image_url: "https://picsum.photos/id/1003/800/600",
      url: "https://example.com/demo/black-slip",
      description:
        "Minimal elevated black slip dress with clean lines for dinner, date night, and polished evening styling."
    },
    %{
      source_id: "demo:minimal-blazer-01",
      title: "Everlane Minimal Wool Blazer - Elevated Neutral",
      brand: "Everlane",
      size: "M",
      condition: "used",
      price: "96.00",
      source: "ebay",
      image_url: "https://picsum.photos/id/1018/800/600",
      url: "https://example.com/demo/wool-blazer",
      description:
        "Soft neutral blazer for elevated minimal outfits, dinner layers, and tailored second-hand styling."
    },
    %{
      source_id: "demo:silk-blouse-01",
      title: "Cream Silk Blouse - Minimal Dinner Top",
      brand: "Equipment",
      size: "M",
      condition: "used",
      price: "72.00",
      source: "poshmark",
      image_url: "https://picsum.photos/id/1005/800/600",
      url: "https://example.com/demo/silk-blouse",
      description:
        "Cream silk blouse with quiet luxury feel, pairs with trousers or denim for elevated dinner looks."
    },
    %{
      source_id: "demo:cargo-pants-01",
      title: "Olive Cargo Pants - Y2K Streetwear",
      brand: "Carhartt",
      size: "M",
      condition: "used",
      price: "54.00",
      source: "depop",
      image_url: "https://picsum.photos/id/1012/800/600",
      url: "https://example.com/demo/cargos",
      description:
        "Olive cargo pants with relaxed fit, useful for Y2K and streetwear outfits under budget."
    },
    %{
      source_id: "demo:cashmere-sweater-01",
      title: "Grey Cashmere Crewneck - Minimal Layer",
      brand: "Naadam",
      size: "S",
      condition: "used",
      price: "84.00",
      source: "ebay",
      image_url: "https://picsum.photos/id/1027/800/600",
      url: "https://example.com/demo/cashmere",
      description:
        "Soft grey cashmere sweater for minimal capsule styling and elevated everyday outfits."
    },
    %{
      source_id: "demo:leather-loafer-01",
      title: "Black Leather Loafers - Dinner Outfit",
      brand: "Vagabond",
      size: "8",
      condition: "used",
      price: "88.00",
      source: "poshmark",
      image_url: "https://picsum.photos/id/1041/800/600",
      url: "https://example.com/demo/loafers",
      description:
        "Black leather loafers with polished shape for minimal dinner outfits and smart casual styling."
    },
    %{
      source_id: "demo:windbreaker-01",
      title: "90s Colorblock Windbreaker - Vintage Street",
      brand: "Adidas",
      size: "M",
      condition: "used",
      price: "46.00",
      source: "depop",
      image_url: "https://picsum.photos/id/1035/800/600",
      url: "https://example.com/demo/windbreaker",
      description:
        "Colorblock vintage windbreaker for streetwear, lightweight layering, and nostalgic sportswear looks."
    }
  ]

  def enabled?, do: Application.get_env(:chat_app, :demo_mode, false) == true

  def enable! do
    Application.put_env(:chat_app, :demo_mode, true)
    Application.put_env(:chat_app, :openai_module, ChatApp.OpenAI.DemoStub)
    :ok
  end

  def email, do: @email
  def items, do: @items

  def ensure_seeded! do
    if Repo.aggregate(from(i in Item, where: like(i.source_id, ^"#{@source_id_prefix}%")), :count) ==
         0 do
      seed!().user
    else
      ensure_demo_user!()
    end
  end

  def seed! do
    user = ensure_demo_user!()
    reset_demo_items!()

    inserted =
      Enum.map(@items, fn attrs ->
        item =
          %Item{}
          |> Item.changeset(Map.put(attrs, :last_scraped_at, DateTime.utc_now(:second)))
          |> Repo.insert!()

        :ok = FTS5Index.upsert(item.id)
        :ok = VectorStore.upsert(item.id, vector_for_text(item_text(item)))
        insert_price_history!(item)
        item
      end)

    seed_saved_items!(user.id, inserted)
    seed_preferences!(user.id)

    %{user: user, items: inserted}
  end

  def ensure_demo_user! do
    case Repo.get_by(User, email: @email) do
      nil ->
        %User{}
        |> User.email_changeset(%{email: @email}, validate_unique: false)
        |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
        |> Repo.insert!()

      user ->
        user
    end
  end

  def vector_for_text(text) when is_binary(text) do
    text
    |> tokenize()
    |> Enum.reduce(List.duplicate(0.0, 512), &add_token_weight/2)
    |> normalize_vector()
  end

  def scripted_card_ids(user_message, limit \\ 4) do
    query_vector = vector_for_text(user_message)

    @items
    |> Enum.map(fn attrs ->
      score = cosine(query_vector, vector_for_text(item_text(attrs)))
      {attrs.source_id, score}
    end)
    |> Enum.sort_by(fn {_source_id, score} -> score end, :desc)
    |> Enum.take(limit)
    |> Enum.flat_map(fn {source_id, _score} ->
      case Repo.get_by(Item, source_id: source_id) do
        nil -> []
        item -> [item.id]
      end
    end)
  end

  defp seed_saved_items!(user_id, items) do
    items
    |> Enum.take(3)
    |> Enum.each(fn item ->
      _ = Clothing.save_item(user_id, item.id, item.price)
    end)
  end

  defp seed_preferences!(user_id) do
    {:ok, _preferences} =
      Accounts.save_preferences(user_id, %{
        "sizes" => ["S", "M"],
        "brands" => "Nike, Levi's, Reformation",
        "budget_min" => "10",
        "budget_max" => "150",
        "style_keywords" => "vintage, street, minimal"
      })

    :ok
  end

  defp reset_demo_items! do
    demo_rows =
      Item
      |> where([i], like(i.source_id, ^"#{@source_id_prefix}%"))
      |> select([i], {i.id, i.title})
      |> Repo.all()

    demo_ids = Enum.map(demo_rows, fn {id, _title} -> id end)

    if demo_ids != [] do
      Repo.delete_all(from(s in Clothing.SavedItem, where: s.item_id in ^demo_ids))
      Repo.delete_all(from(p in PriceHistory, where: p.item_id in ^demo_ids))

      Enum.each(demo_rows, fn {id, title} ->
        Repo.query!(
          "INSERT INTO clothing_fts(clothing_fts, rowid, title) VALUES ('delete', ?, ?)",
          [id, title]
        )

        Repo.query!("DELETE FROM clothing_vec WHERE rowid = ?", [id])
      end)

      Repo.query!(
        "DELETE FROM clothing_fts_meta WHERE item_id IN (#{placeholders(demo_ids)})",
        demo_ids
      )
    end

    Repo.delete_all(from(i in Item, where: like(i.source_id, ^"#{@source_id_prefix}%")))
  end

  defp insert_price_history!(item) do
    now = DateTime.utc_now(:microsecond)

    Enum.each([Decimal.mult(item.price, Decimal.new("1.12")), item.price], fn price ->
      Repo.insert!(%PriceHistory{
        item_id: item.id,
        price: Decimal.round(price, 2),
        currency: "USD",
        inserted_at: now
      })
    end)
  end

  defp item_text(%Item{} = item) do
    "#{item.title} #{item.brand} #{item.size} #{item.condition} #{item.price} #{item.source} #{item.description}"
  end

  defp item_text(attrs) do
    "#{attrs.title} #{attrs.brand} #{attrs.size} #{attrs.condition} #{attrs.price} #{attrs.source} #{attrs.description}"
  end

  defp tokenize(text) do
    ~r/[a-z0-9']+/
    |> Regex.scan(String.downcase(text))
    |> List.flatten()
  end

  defp add_token_weight(token, vector) do
    Enum.reduce(token_dimensions(token), vector, fn {index, weight}, acc ->
      List.update_at(acc, index, &(&1 + weight))
    end)
  end

  defp token_dimensions(token) do
    semantic =
      cond do
        token in ["vintage", "90s", "faded", "retro", "preloved"] ->
          [{0, 3.0}]

        token in ["jeans"] ->
          [{1, 5.0}]

        token in ["denim", "jacket", "trucker", "chore", "levi", "levi's", "501", "505", "straight"] ->
          [{1, 3.0}]

        token in ["streetwear", "street", "y2k", "cargo", "sneakers", "windbreaker"] ->
          [{2, 3.0}]

        token in ["minimal", "elevated", "dinner", "silk", "blazer", "slip", "loafers"] ->
          [{3, 3.0}]

        token in ["under", "budget", "100", "150"] ->
          [{4, 2.0}]

        true ->
          []
      end

    hash_index = 16 + :erlang.phash2(token, 496)
    [{hash_index, 1.0} | semantic]
  end

  defp normalize_vector(vector) do
    norm =
      vector
      |> Enum.map(&(&1 * &1))
      |> Enum.sum()
      |> :math.sqrt()

    if norm < 1.0e-10 do
      [1.0 | List.duplicate(0.0, 511)]
    else
      Enum.map(vector, &(&1 / norm))
    end
  end

  defp cosine(left, right) do
    left
    |> Enum.zip(right)
    |> Enum.map(fn {a, b} -> a * b end)
    |> Enum.sum()
  end

  defp placeholders(values), do: values |> Enum.map(fn _ -> "?" end) |> Enum.join(",")
end
