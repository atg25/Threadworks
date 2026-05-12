defmodule ChatApp.SP0002CoreSchemaE2ETest do
  use ChatApp.DataCase, async: false

  @moduletag :e2e

  # Minimal Oban worker used only in E1. Must be defined at compile time so
  # Oban can resolve the worker module atom from job records.
  defmodule MinimalWorker do
    use Oban.Worker, queue: :default

    @impl Oban.Worker
    def perform(%Oban.Job{}), do: :ok
  end

  # -- E1 ----------------------------------------------------------------------

  # E1
  test "happy path — Oban jobs table accepts a job insert" do
    # In :inline testing mode Oban still writes to oban_jobs before executing.
    # A schema mismatch (wrong Oban.Migration version) surfaces here as an
    # Ecto.ConstraintError or DBConnection.ConnectionError.
    assert {:ok, _job} = Oban.insert(MinimalWorker.new(%{test: true}))
  end

  # -- E2 ----------------------------------------------------------------------

  # E2
  # The spec requires source to be NOT NULL — this test documents and enforces
  # that decision. If source is nullable the migration is under-constrained.
  test "inserting a clothing_item without source raises a NOT NULL constraint error" do
    ts = "2026-05-06 00:00:00"

    assert {:error, %{message: msg}} =
             Ecto.Adapters.SQL.query(
               ChatApp.Repo,
               """
               INSERT INTO clothing_items
                 (title, brand, price, url, source, inserted_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)
               """,
               ["Test", "Brand", "10.00", "http://example.com", nil, ts, ts]
             )

    assert msg =~ "NOT NULL constraint failed",
           "Expected NOT NULL violation for source=nil, got: #{msg}"
  end
end
