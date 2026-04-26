defmodule ChatApp.Sprint14HardeningToolingUnitTest do
  use ExUnit.Case, async: true

  alias ChatAppWeb.Endpoint
  alias ChatAppWeb.Router

  test "Router pipelines list contains :browser only" do
    assert router_pipelines() == [:browser]
  end

  test "Router has a non-stale @moduledoc" do
    doc = moduledoc_for(Router)

    assert is_binary(doc)
    assert String.length(doc) > 100
    assert String.contains?(doc, "single browser pipeline")
  end

  test "Endpoint has a non-stale @moduledoc" do
    doc = moduledoc_for(Endpoint)

    assert is_binary(doc)
    assert String.contains?(doc, "SECRET_KEY_BASE")
  end

  defp router_pipelines do
    Router.__info__(:functions)
    |> Enum.filter(fn {name, arity} -> arity == 2 and name in [:browser, :api] end)
    |> Enum.map(fn {name, _arity} -> name end)
    |> Enum.sort()
  end

  defp moduledoc_for(module) do
    {:docs_v1, _, _, _, moduledoc, _, _} = Code.fetch_docs(module)

    case moduledoc do
      %{"en" => text} when is_binary(text) -> text
      _ -> nil
    end
  end
end
