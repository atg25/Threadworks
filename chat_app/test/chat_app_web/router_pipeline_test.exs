defmodule ChatAppWeb.RouterPipelineTest do
  use ExUnit.Case, async: true

  test "Router pipelines list contains :browser only" do
    router_source =
      Path.join([File.cwd!(), "lib", "chat_app_web", "router.ex"])
      |> File.read!()

    assert router_source =~ "pipeline :browser"
    refute router_source =~ "pipeline :api"

    pipe_throughs =
      Regex.scan(~r/pipe_through\s+:([a-zA-Z0-9_]+)/, router_source, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_atom/1)
      |> Enum.uniq()

    assert pipe_throughs == [:browser]
  end

  test "Router has a non-stale @moduledoc" do
    assert {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(ChatAppWeb.Router)
    assert is_binary(moduledoc)
    assert byte_size(moduledoc) > 100
    assert String.contains?(moduledoc, "browser")
  end

  test "Endpoint has a non-stale @moduledoc" do
    assert {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(ChatAppWeb.Endpoint)
    assert is_binary(moduledoc)
    assert String.contains?(moduledoc, "SECRET_KEY_BASE")
  end
end
