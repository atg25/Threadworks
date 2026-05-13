defmodule ChatAppWeb.UserLive.SettingsTest do
  use ChatAppWeb.ConnCase

  alias ChatApp.Accounts
  alias ChatApp.Accounts.UserPreferences
  alias ChatApp.Repo
  import Phoenix.LiveViewTest
  import ChatApp.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Password updated successfully"

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "preferences form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "preferences_form_happy_path_persists_and_renders", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
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

      assert result =~ "Preferences saved"

      preferences = Repo.get_by!(UserPreferences, user_id: user.id)
      assert Jason.decode!(preferences.sizes) == ["S", "M"]
      assert Jason.decode!(preferences.brands) == ["Nike", "Reformation"]
      assert Jason.decode!(preferences.style_keywords) == ["vintage", "street"]
      assert preferences.budget_min == Decimal.new("10.00")
      assert preferences.budget_max == Decimal.new("150.00")

      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ ~s(id="preferences_sizes_s")
      assert html =~ ~s(checked)
      assert html =~ ~s(value="Nike, Reformation")
      assert html =~ ~s(value="10")
      assert html =~ ~s(value="150")
      assert html =~ ~s(value="vintage, street")
    end

    test "preferences_persist_sizes_as_json_array and re-mount checks boxes", %{
      conn: conn,
      user: user
    } do
      assert {:ok, _preferences} =
               Accounts.save_preferences(user.id, %{"sizes" => ["S", "M", "L"]})

      preferences = Repo.get_by!(UserPreferences, user_id: user.id)
      assert Jason.decode!(preferences.sizes) == ["S", "M", "L"]

      {:ok, _lv, html} = live(conn, ~p"/users/settings")
      assert html =~ ~s(id="preferences_sizes_s")
      assert html =~ ~s(id="preferences_sizes_m")
      assert html =~ ~s(id="preferences_sizes_l")
      assert html =~ ~s(value="S" checked)
      assert html =~ ~s(value="M" checked)
      assert html =~ ~s(value="L" checked)
    end

    test "preferences_rejects_non_numeric_budget_values with field error", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#preferences_form")
        |> render_submit(%{
          "preferences" => %{"budget_min" => "abc", "budget_max" => "50"}
        })

      assert result =~ "Could not save preferences"
      assert result =~ "must be a number"
      refute Repo.get_by(UserPreferences, user_id: user.id)
    end

    test "preferences_rejects_budget_min_greater_than_max with field error", %{
      conn: conn,
      user: user
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#preferences_form")
        |> render_submit(%{
          "preferences" => %{"budget_min" => "100", "budget_max" => "50"}
        })

      assert result =~ "Could not save preferences"
      assert result =~ "must be less than or equal to budget max"
      refute Repo.get_by(UserPreferences, user_id: user.id)
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
