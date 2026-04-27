defmodule ChatAppWeb.Sprint14HardeningToolingIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  alias ChatAppWeb.Router

  test "GET / still returns 200 after pipeline cleanup", %{conn: conn} do
    conn = get(conn, "/")

    assert html_response(conn, 200) =~ "id=\"chat-input\""
    assert router_pipelines() == [:browser]
  end

  test "GET /api/* returns 404 (no api scope wired)", %{conn: conn} do
    conn = get(conn, "/api/anything")

    assert html_response(conn, 404)

    assert router_pipelines() == [:browser]
  end

  test "mix docs runs without warnings on the five web modules" do
    modules = [
      "ChatAppWeb.ChatLive",
      "ChatAppWeb.Router",
      "ChatAppWeb.Endpoint",
      "ChatAppWeb.Layouts",
      "ChatAppWeb.CoreComponents"
    ]

    {output, status} =
      System.cmd("mix", ["docs"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    warning_lines =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(fn line ->
        String.contains?(line, "warning:") and Enum.any?(modules, &String.contains?(line, &1))
      end)

    assert status == 0
    assert warning_lines == []
  end

  defp router_pipelines do
    Router.__info__(:functions)
    |> Enum.filter(fn {name, arity} -> arity == 2 and name in [:browser, :api] end)
    |> Enum.map(fn {name, _arity} -> name end)
    |> Enum.sort()
  end
end
