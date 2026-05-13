defmodule SP0505PreferencesIntegrationTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.AccountsFixtures
  alias ChatApp.Repo

  describe "SP-05-05 integration" do
    test "preferences_form_happy_path_persists_and_renders", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> element("#preferences_form")
      |> render_submit(%{
        "preferences" => %{
          "sizes" => ["S", "M"],
          "brands" => "Nike, Reformation",
          "budget_min" => "10",
          "budget_max" => "150",
          "style_keywords" => "vintage, street"
        }
      })

      row = fetch_preferences_row!(user.id)

      assert decode_json_array(row["sizes"]) == ["S", "M"]
      assert decode_json_array(row["brands"]) == ["Nike", "Reformation"]
      assert decode_json_array(row["style_keywords"]) == ["vintage", "street"]
      assert row["budget_min"] == "10.00"
      assert row["budget_max"] == "150.00"

      {:ok, _reloaded_view, reloaded_html} = live(conn, ~p"/users/settings")

      assert reloaded_html =~ ~s(value="Nike, Reformation")
      assert reloaded_html =~ ~s(value="10")
      assert reloaded_html =~ ~s(value="150")
      assert reloaded_html =~ ~s(value="vintage, street")
      assert reloaded_html =~ ~s(value="S" checked)
      assert reloaded_html =~ ~s(value="M" checked)
    end

    test "preferences_handles_empty_optional_fields", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> element("#preferences_form")
      |> render_submit(%{
        "preferences" => %{
          "sizes" => ["M"],
          "brands" => "",
          "style_keywords" => ""
        }
      })

      row = fetch_preferences_row!(user.id)

      assert decode_json_array(row["brands"]) == []
      assert decode_json_array(row["style_keywords"]) == []

      html = render(view)
      refute html =~ "500"
    end
  end

  defp fetch_preferences_row!(user_id) do
    %{rows: [row], columns: columns} =
      Repo.query!(
        "SELECT sizes, brands, budget_min, budget_max, style_keywords FROM user_preferences WHERE user_id = ?",
        [user_id]
      )

    Enum.zip(columns, row) |> Map.new()
  end

  defp decode_json_array(nil), do: []

  defp decode_json_array(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _ -> []
    end
  end
end
