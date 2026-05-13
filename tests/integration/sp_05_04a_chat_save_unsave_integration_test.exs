defmodule SP0504aChatSaveUnsaveIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  describe "SP-05-04a integration" do
    test "chat_live_handle_save_item_updates_assigns", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "sp-05-04a-int-save"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")
      prepare_card(view, item.id)

      view
      |> element("[phx-click='save_item'][phx-value-item-id='#{item.id}']")
      |> render_click()

      assert MapSet.member?(live_assigns(view).saved_item_ids, item.id)

      count =
        Repo.aggregate(
          from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
          :count
        )

      assert count == 1
    end

    test "chat_live_handle_unsave_item_updates_assigns", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "sp-05-04a-int-unsave"})

      Repo.query!(
        "INSERT INTO saved_items (user_id, item_id, price_at_save, inserted_at) VALUES (?, ?, ?, ?)",
        [user.id, item.id, "25.00", "2026-05-13 00:00:00"]
      )

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")
      prepare_card(view, item.id)

      view
      |> element("[phx-click='unsave_item'][phx-value-item-id='#{item.id}']")
      |> render_click()

      refute MapSet.member?(live_assigns(view).saved_item_ids, item.id)

      count =
        Repo.aggregate(
          from(s in "saved_items", where: s.user_id == ^user.id and s.item_id == ^item.id),
          :count
        )

      assert count == 0
    end
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp prepare_card(view, item_id) do
    view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => "show card"})
    send(view.pid, {:stream_token, ~s({"cards":[{"item_id":#{item_id},"reason":"test"}]})})
    send(view.pid, :stream_done)
    _ = render(view)
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "SP-05-04a Integration Item #{System.unique_integer([:positive])}",
          brand: "Threadworks",
          price: Decimal.new("39.00"),
          url: "https://example.com/item-#{System.unique_integer([:positive])}",
          source: "ebay",
          source_id: "source-#{System.unique_integer([:positive])}"
        },
        overrides
      )

    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert!()
  end
end
