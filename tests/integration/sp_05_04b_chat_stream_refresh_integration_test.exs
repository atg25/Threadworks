defmodule SP0504bChatStreamRefreshIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  describe "SP-05-04b integration" do
    test "chat_live_attaches_pending_cards_integration", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item_one = item_fixture(%{source_id: "sp-05-04b-int-1"})
      item_two = item_fixture(%{source_id: "sp-05-04b-int-2"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => "show cards"})

      send(
        view.pid,
        {:stream_token,
         ~s({"cards":[{"item_id":#{item_one.id},"reason":"integration-r1"},{"item_id":#{item_two.id},"reason":"integration-r2"}]})}
      )

      send(view.pid, :stream_done)
      _ = render(view)

      assigns = live_assigns(view)
      assistant = assigns.messages |> Enum.reverse() |> Enum.find(&(&1.role == :assistant))

      assert assistant
      assert length(assistant.cards) == 2

      html = render(view)
      assert html =~ "integration-r1"
      assert html =~ "integration-r2"

      {:ok, reloaded, _html} = live(conn, "/")
      reloaded_assigns = live_assigns(reloaded)
      reloaded_assistant = reloaded_assigns.messages |> Enum.reverse() |> Enum.find(&(&1.role == :assistant))

      assert reloaded_assistant
      assert is_list(reloaded_assistant.cards)
      assert length(reloaded_assistant.cards) == 2
    end
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "SP-05-04b Integration Item #{System.unique_integer([:positive])}",
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
