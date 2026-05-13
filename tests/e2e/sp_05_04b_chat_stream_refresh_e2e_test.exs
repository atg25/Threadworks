defmodule SP0504bChatStreamRefreshE2ETest do
  use ChatAppWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Clothing.Item
  alias ChatApp.Repo

  describe "SP-05-04b e2e" do
    test "stream_attach_happy_path", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      item_one = item_fixture(%{source_id: "sp-05-04b-e2e-stream-1"})
      item_two = item_fixture(%{source_id: "sp-05-04b-e2e-stream-2"})

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      view |> element("form[data-chat-composer-form]") |> render_submit(%{"input" => "show stream cards"})

      send(
        view.pid,
        {:stream_token, ~s({"cards":[{"item_id":#{item_one.id},"reason":"stream-r1"}]})}
      )

      mid_html = render(view)
      assert mid_html =~ "stream-r1"
      assert mid_html =~ "data-product-card"

      send(
        view.pid,
        {:stream_token, ~s({"cards":[{"item_id":#{item_two.id},"reason":"stream-r2"}]})}
      )

      send(view.pid, :stream_done)
      final_html = render(view)

      assert final_html =~ "stream-r1"
      assert final_html =~ "stream-r2"
      assert final_html =~ "data-product-card"

      {:ok, reloaded, _html} = live(conn, "/")
      reloaded_html = render(reloaded)
      assert reloaded_html =~ "data-product-card"
    end

    test "refresh_listings_shows_flash_and_enqueues_jobs (edge)", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      original = Application.get_env(:chat_app, :scrape_queries)

      on_exit(fn ->
        Application.put_env(:chat_app, :scrape_queries, original)
      end)

      Application.put_env(:chat_app, :scrape_queries, [
        %{"source" => "ebay", "query" => "vintage"},
        %{"source" => "depop", "query" => "vintage"},
        %{"source" => "poshmark", "query" => "vintage"}
      ])

      before_count =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker"),
          :count
        )

      _ = render_hook(view, "refresh_listings", %{})
      html = render(view)

      assert html =~ "Refreshing listings in the background"

      after_count =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker"),
          :count
        )

      assert after_count - before_count == 3
      refute html =~ "500"
    end

    test "refresh_listings_handles_missing_config_gracefully (edge)", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/")

      original = Application.get_env(:chat_app, :scrape_queries)

      on_exit(fn ->
        Application.put_env(:chat_app, :scrape_queries, original)
      end)

      Application.put_env(:chat_app, :scrape_queries, nil)

      before_count =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker"),
          :count
        )

      _ = render_hook(view, "refresh_listings", %{})
      html = render(view)

      assert html =~ "No sources configured"

      after_count =
        Repo.aggregate(
          from(j in Oban.Job, where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker"),
          :count
        )

      assert after_count == before_count
      refute html =~ "500"
    end
  end

  defp item_fixture(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "SP-05-04b E2E Item #{System.unique_integer([:positive])}",
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
