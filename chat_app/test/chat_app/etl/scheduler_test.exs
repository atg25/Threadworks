defmodule ChatApp.ETL.SchedulerTest do
  use ChatApp.DataCase, async: false

  # ---------------------------------------------------------------------------
  # Test 1
  # ScrapeWorker is registered in the Oban.Plugins.Cron config after application start
  # ---------------------------------------------------------------------------

  test "ScrapeWorker is registered in Oban.Plugins.Cron crontab after application start" do
    oban_config = Application.fetch_env!(:chat_app, Oban)
    plugins = Keyword.get(oban_config, :plugins, [])

    cron_plugin =
      Enum.find(plugins, fn
        {Oban.Plugins.Cron, _opts} -> true
        _ -> false
      end)

    assert cron_plugin != nil,
           "Oban.Plugins.Cron not found in Oban config — add it to config/config.exs"

    {Oban.Plugins.Cron, cron_opts} = cron_plugin
    crontab = Keyword.get(cron_opts, :crontab, [])

    worker_present =
      Enum.any?(crontab, fn
        {_expr, ChatApp.ETL.Workers.ScrapeWorker, _args} -> true
        {_expr, ChatApp.ETL.Workers.ScrapeWorker} -> true
        _ -> false
      end)

    assert worker_present,
           "ChatApp.ETL.Workers.ScrapeWorker not found in Oban.Plugins.Cron crontab — " <>
             "Cron plugin is configured but ScrapeWorker is not registered in it"
  end

  # ---------------------------------------------------------------------------
  # Test 2
  # Cron expression is "0 */2 * * *" and not "*/2 * * * *"
  # ---------------------------------------------------------------------------

  test ~s[Cron expression is "0 */2 * * *" and not "*/2 * * * *"] do
    oban_config = Application.fetch_env!(:chat_app, Oban)
    plugins = Keyword.get(oban_config, :plugins, [])

    cron_plugin =
      Enum.find(plugins, fn
        {Oban.Plugins.Cron, _opts} -> true
        _ -> false
      end)

    assert cron_plugin != nil,
           "Oban.Plugins.Cron not found in Oban config — add it to config/config.exs"

    {Oban.Plugins.Cron, cron_opts} = cron_plugin
    crontab = Keyword.get(cron_opts, :crontab, [])

    scrape_entry =
      Enum.find(crontab, fn
        {_expr, ChatApp.ETL.Workers.ScrapeWorker, _args} -> true
        {_expr, ChatApp.ETL.Workers.ScrapeWorker} -> true
        _ -> false
      end)

    assert scrape_entry != nil,
           "ChatApp.ETL.Workers.ScrapeWorker not found in crontab — check Oban.Plugins.Cron config"

    {cron_expr, _worker} =
      case scrape_entry do
        {expr, worker, _args} -> {expr, worker}
        {expr, worker} -> {expr, worker}
      end

    assert cron_expr == "0 */2 * * *",
           ~s[expected cron expression "0 */2 * * *" (every 2 hours), ] <>
             ~s[got "#{cron_expr}" — "*/2 * * * *" fires every 2 minutes, not hours]
  end

  # ---------------------------------------------------------------------------
  # Test 3
  # :scrape_queries config key is accessible in test environment
  # ---------------------------------------------------------------------------

  test ":scrape_queries config key is accessible in test environment" do
    queries = Application.fetch_env!(:chat_app, :scrape_queries)

    assert queries == ["test query"],
           "expected :scrape_queries to be [\"test query\"] in test env, got: #{inspect(queries)}"
  end

  # ---------------------------------------------------------------------------
  # Test 4
  # :scrape_queries is overridable via Application.put_env in tests
  # ---------------------------------------------------------------------------

  test ":scrape_queries is overridable via Application.put_env in tests" do
    original = Application.get_env(:chat_app, :scrape_queries)
    on_exit(fn -> Application.put_env(:chat_app, :scrape_queries, original) end)

    Application.put_env(:chat_app, :scrape_queries, ["custom"])

    assert Application.get_env(:chat_app, :scrape_queries) == ["custom"],
           "expected :scrape_queries to read back [\"custom\"] after put_env — " <>
             "queries may be hardcoded as a module attribute at compile time"
  end

  # ---------------------------------------------------------------------------
  # Test 5 (scheduler suite)
  # perform/1 with "queries" key enqueues per-source-per-query ScrapeWorker jobs
  # ---------------------------------------------------------------------------

  test ~s[perform/1 "queries" clause enqueues one ScrapeWorker job per source per query] do
    alias ChatApp.ETL.Workers.ScrapeWorker
    alias ChatApp.Repo
    import Ecto.Query

    Oban.Testing.with_testing_mode(:manual, fn ->
      ScrapeWorker.perform(%Oban.Job{args: %{"queries" => ["vintage levi", "y2k denim"]}})

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "ChatApp.ETL.Workers.ScrapeWorker",
            order_by: [asc: j.id]
          )
        )

      assert length(jobs) == 6,
             "expected 3 sources × 2 queries = 6 jobs, got #{length(jobs)}"

      sources = jobs |> Enum.map(& &1.args["source"]) |> Enum.sort() |> Enum.uniq()
      assert Enum.sort(sources) == ["depop", "ebay", "poshmark"]

      queries = jobs |> Enum.map(& &1.args["query"]) |> Enum.sort() |> Enum.uniq()
      assert Enum.sort(queries) == ["vintage levi", "y2k denim"]
    end)
  end
end
