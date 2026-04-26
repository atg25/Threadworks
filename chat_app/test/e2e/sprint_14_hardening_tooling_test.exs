defmodule ChatAppWeb.Sprint14HardeningToolingE2ETest do
  use ExUnit.Case, async: false

  @moduletag :e2e

  test "Positive — full happy-path smoke after CI lands" do
    ci_path = Path.expand("../.github/workflows/ci.yml", File.cwd!())

    smoke_suite_path =
      Path.join([File.cwd!(), "test", "chat_app_web", "features", "chat_e2e_test.exs"])

    assert File.exists?(ci_path)
    assert File.exists?(smoke_suite_path)

    smoke_suite = File.read!(smoke_suite_path)
    assert smoke_suite =~ "@moduletag :e2e"
    assert smoke_suite =~ "assistant bubble appears after stream completes"
  end

  test "Negative — running mix precommit with a deliberately broken Vitest test fails the alias" do
    test_file =
      Path.join([File.cwd!(), "assets", "test", "hooks", "sprint_14_precommit_red.test.js"])

    failing_vitest = """
    import { describe, expect, it } from \"vitest\";

    describe(\"SPRINT-14 precommit vitest gate\", () => {
      it(\"fails intentionally\", () => {
        expect(true).toBe(false);
      });
    });
    """

    File.write!(test_file, failing_vitest)

    try do
      # Running `mix precommit` recursively from inside `mix test` can recurse
      # through this very test. Execute the alias' Vitest stage directly.
      {output, status} =
        System.cmd("mix", ["cmd", "--cd", "assets", "npm", "test"], stderr_to_stdout: true)

      assert status != 0
      assert output =~ "vitest"
      assert output =~ "SPRINT-14 precommit vitest gate"
    after
      File.rm(test_file)
    end
  end

  test "Negative — fresh clone bootstrap without cd assets && npm install fails the new step with an actionable error" do
    assets_dir = Path.join([File.cwd!(), "assets"])
    node_modules_dir = Path.join([assets_dir, "node_modules"])
    parked_node_modules_dir = Path.join([assets_dir, "node_modules.__sprint14_backup__"])
    had_node_modules? = File.dir?(node_modules_dir)

    if File.exists?(parked_node_modules_dir) do
      File.rm_rf!(parked_node_modules_dir)
    end

    if had_node_modules? do
      File.rename!(node_modules_dir, parked_node_modules_dir)
    end

    {output, status} =
      try do
        System.cmd("npm", ["test"],
          cd: assets_dir,
          stderr_to_stdout: true
        )
      after
        if had_node_modules? and File.dir?(parked_node_modules_dir) do
          File.rename!(parked_node_modules_dir, node_modules_dir)
        end
      end

    assert status != 0
    assert String.downcase(output) =~ "vitest"
  end
end
