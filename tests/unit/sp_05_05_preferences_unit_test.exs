defmodule SP0505PreferencesUnitTest do
  use ChatAppWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ChatApp.Accounts
  alias ChatApp.AccountsFixtures
  alias ChatApp.Repo

  describe "SP-05-05 unit" do
    test "preferences_parse_brands_trims_and_filters_empty_tokens" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, _prefs} =
               Accounts.save_preferences(user.id, %{
                 "brands" => "Nike,  , Adidas,,Reformation "
               })

      row = fetch_preferences_row!(user.id)
      assert decode_json_array(row["brands"]) == ["Nike", "Adidas", "Reformation"]
    end

    test "preferences_persist_sizes_as_json_array", %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/settings")

      view
      |> element("#preferences_form")
      |> render_submit(%{
        "preferences" => %{
          "sizes" => ["S", "M", "L"]
        }
      })

      row = fetch_preferences_row!(user.id)
      assert decode_json_array(row["sizes"]) == ["S", "M", "L"]

      {:ok, remount, remount_html} = live(conn, ~p"/users/settings")
      _ = remount

      assert remount_html =~ ~s(value="S")
      assert remount_html =~ ~s(value="M")
      assert remount_html =~ ~s(value="L")
      assert remount_html =~ ~s(value="S" checked)
      assert remount_html =~ ~s(value="M" checked)
      assert remount_html =~ ~s(value="L" checked)
    end

    test "preferences_rejects_non_numeric_budget_values" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Accounts.save_preferences(user.id, %{
                 "budget_min" => "abc",
                 "budget_max" => "50"
               })

      refute changeset.errors[:budget_min] == nil
      refute preference_row_exists?(user.id)
    end

    test "preferences_rejects_budget_min_greater_than_max" do
      user = AccountsFixtures.user_fixture()

      assert {:error, changeset} =
               Accounts.save_preferences(user.id, %{
                 "budget_min" => "100",
                 "budget_max" => "50"
               })

      refute changeset.errors[:budget_min] == nil and changeset.errors[:budget_max] == nil
      refute preference_row_exists?(user.id)
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

  defp preference_row_exists?(user_id) do
    %{rows: [[count]]} =
      Repo.query!("SELECT COUNT(*) FROM user_preferences WHERE user_id = ?", [user_id])

    count > 0
  end

  defp decode_json_array(nil), do: []

  defp decode_json_array(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _ -> []
    end
  end
end
