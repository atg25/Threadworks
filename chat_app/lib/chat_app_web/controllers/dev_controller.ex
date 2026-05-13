defmodule ChatAppWeb.DevController do
  use ChatAppWeb, :controller

  alias ChatApp.Clothing.Item
  alias ChatAppWeb.UserAuth

  @dev Mix.env() == :dev

  def product_card(conn, _params) do
    item = %Item{
      id: 9999,
      title: "Dev Jacket",
      brand: "Acme",
      size: "L",
      condition: "good",
      price: Decimal.new("49.99"),
      source: "store",
      url: "https://example.com/dev/1",
      image_url: nil
    }

    render(conn, "product_card.html",
      item: item,
      reason: "Dev QA: placeholder shown",
      saved: false
    )
  end

  def demo_login(conn, _params) do
    if @dev do
      ChatApp.Demo.enable!()
      user = ChatApp.Demo.ensure_seeded!()

      conn
      |> put_flash(
        :info,
        "Demo mode enabled. Seeded catalog, RAG retrieval, saved items, and preferences are ready."
      )
      |> UserAuth.log_in_user(user)
    else
      send_resp(conn, 404, "not found")
    end
  end
end
