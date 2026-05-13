defmodule SP0504bChatStreamRefreshUnitTest do
  use ChatAppWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  describe "SP-05-04b unit" do
    test "chat_live_attaches_pending_cards_after_streaming_unit", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item = item_fixture(%{source_id: "sp-05-04b-unit-attach"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      send(
        view.pid,
        {:stream_token, ~s({"cards":[{"item_id":#{item.id},"reason":"unit-card-reason"}]})}
      )

      send(view.pid, :stream_done)
      _ = render(view)

      assigns = live_assigns(view)
      refute assigns.pending_cards != []

      assistant =
        assigns.messages
        |> Enum.reverse()
        |> Enum.find(&(&1.role == :assistant))

      assert assistant
      assert is_list(assistant.cards)
      assert length(assistant.cards) == 1
      assert hd(assistant.cards).item.id == item.id
      assert hd(assistant.cards).reason == "unit-card-reason"
    end

    test "refresh_listings_enqueues_one_job_per_source_unit", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      original = Application.get_env(:chat_app, :scrape_queries)

      on_exit(fn ->
        Application.put_env(:chat_app, :scrape_queries, original)
      end)

      Application.put_env(:chat_app, :scrape_queries, [
        %{"source" => "ebay", "query" => "vintage levi"},
        %{"source" => "depop", "query" => "vintage levi"},
        %{"source" => "poshmark", "query" => "vintage levi"}
      ])

      Oban.Testing.with_testing_mode(:manual, fn ->
        _ = render_hook(view, "refresh_listings", %{})

        count =
          Repo.aggregate(
            from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker"),
            :count
          )

        assert count == 3
      end)
    end
  end

  defp live_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "SP-05-04b Unit Item #{System.unique_integer([:positive])}",
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
