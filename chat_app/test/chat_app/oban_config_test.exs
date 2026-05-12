defmodule ChatApp.ObanConfigTest do
  use ChatApp.DataCase, async: false

  # U1
  test "oban config has scraper queue with concurrency 3" do
    queues = Application.fetch_env!(:chat_app, Oban)[:queues]
    assert queues[:scraper] == 3
  end

  # U2
  test "oban config has embedder queue with concurrency 5" do
    queues = Application.fetch_env!(:chat_app, Oban)[:queues]
    assert queues[:embedder] == 5
  end

  # U3
  test "oban config repo is ChatApp.Repo" do
    repo = Application.fetch_env!(:chat_app, Oban)[:repo]
    assert repo == ChatApp.Repo
  end

  # U4
  test "Oban process is running after application start" do
    assert is_pid(Oban.Registry.whereis(Oban))
  end

  # U5
  test "Oban test config uses inline mode" do
    assert Application.fetch_env!(:chat_app, Oban)[:testing] == :inline
  end

  # U6
  test "sqlite_vec extension loads on DB connection" do
    result = Ecto.Adapters.SQL.query!(ChatApp.Repo, "SELECT vec_version()", [])
    assert length(result.rows) >= 1
  end

  # U7
  test ".env.example contains all three eBay credential vars" do
    env_example = File.read!(Path.join([__DIR__, "../../.env.example"]))
    assert String.contains?(env_example, "EBAY_APP_ID")
    assert String.contains?(env_example, "EBAY_CERT_ID")
    assert String.contains?(env_example, "EBAY_API_BASE_URL")
  end
end
