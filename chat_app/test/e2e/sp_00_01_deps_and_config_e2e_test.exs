defmodule ChatApp.SP0001DepsAndConfigE2ETest do
  use ExUnit.Case, async: false

  @moduletag :e2e

  # E1
  test "happy path — Oban queues accessible at runtime" do
    queues = Application.fetch_env!(:chat_app, Oban)[:queues]
    assert queues[:scraper] == 3
    assert queues[:embedder] == 5
  end
end
