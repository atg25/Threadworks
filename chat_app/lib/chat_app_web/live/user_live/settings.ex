defmodule ChatAppWeb.UserLive.Settings do
  use ChatAppWeb, :live_view

  on_mount {ChatAppWeb.UserAuth, :require_sudo_mode}

  alias ChatApp.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form for={%{}} id="preferences_form" phx-submit="save_preferences">
        <fieldset>
          <legend class="label mb-1">Sizes</legend>
          <label for="preferences_sizes_s">
            <input
              id="preferences_sizes_s"
              type="checkbox"
              name="preferences[sizes][]"
              value="S"
              checked={"S" in @preferences.sizes}
            /> S
          </label>
          <label for="preferences_sizes_m">
            <input
              id="preferences_sizes_m"
              type="checkbox"
              name="preferences[sizes][]"
              value="M"
              checked={"M" in @preferences.sizes}
            /> M
          </label>
          <label for="preferences_sizes_l">
            <input
              id="preferences_sizes_l"
              type="checkbox"
              name="preferences[sizes][]"
              value="L"
              checked={"L" in @preferences.sizes}
            /> L
          </label>
        </fieldset>

        <label for="preferences_brands">
          <span class="label mb-1">Brands</span>
          <input
            id="preferences_brands"
            type="text"
            name="preferences[brands]"
            value={@preferences.brands}
          />
        </label>

        <label for="preferences_budget_min">
          <span class="label mb-1">Budget min</span>
          <input
            id="preferences_budget_min"
            type="number"
            step="0.01"
            name="preferences[budget_min]"
            value={@preferences.budget_min}
          />
          <p :for={error <- preference_errors(@preference_errors, :budget_min)} class="text-error">
            {error}
          </p>
        </label>

        <label for="preferences_budget_max">
          <span class="label mb-1">Budget max</span>
          <input
            id="preferences_budget_max"
            type="number"
            step="0.01"
            name="preferences[budget_max]"
            value={@preferences.budget_max}
          />
          <p :for={error <- preference_errors(@preference_errors, :budget_max)} class="text-error">
            {error}
          </p>
        </label>

        <label for="preferences_style_keywords">
          <span class="label mb-1">Style keywords</span>
          <input
            id="preferences_style_keywords"
            type="text"
            name="preferences[style_keywords]"
            value={@preferences.style_keywords}
          />
        </label>

        <.button variant="primary" phx-disable-with="Saving...">Save Preferences</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)
    preferences = user.id |> Accounts.get_user_preferences() |> preferences_for_form()

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:preferences, preferences)
      |> assign(:preference_errors, %{})
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("save_preferences", %{"preferences" => attrs}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.save_preferences(user.id, attrs) do
      {:ok, _preferences} ->
        updated_preferences = user.id |> Accounts.get_user_preferences() |> preferences_for_form()

        {:noreply,
         socket
         |> assign(:preferences, updated_preferences)
         |> assign(:preference_errors, %{})
         |> put_flash(:info, "Preferences saved")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:preference_errors, preference_errors_from_changeset(changeset))
         |> put_flash(:error, "Could not save preferences")}
    end
  end

  defp preferences_for_form(nil) do
    %{sizes: [], brands: "", budget_min: "", budget_max: "", style_keywords: ""}
  end

  defp preferences_for_form(preferences) do
    %{
      sizes: decode_json_array(preferences.sizes),
      brands: join_csv(preferences.brands),
      budget_min: decimal_for_input(preferences.budget_min),
      budget_max: decimal_for_input(preferences.budget_max),
      style_keywords: join_csv(preferences.style_keywords)
    }
  end

  defp decode_json_array(nil), do: []

  defp decode_json_array(raw) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, decoded} when is_list(decoded) -> decoded
      _ -> []
    end
  end

  defp join_csv(raw) do
    raw
    |> decode_json_array()
    |> Enum.join(", ")
  end

  defp decimal_for_input(nil), do: ""
  defp decimal_for_input(value) when is_binary(value), do: trim_decimal_string(value)
  defp decimal_for_input(value), do: value |> Decimal.to_string(:normal) |> trim_decimal_string()

  defp trim_decimal_string(value) do
    value
    |> String.trim()
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp preference_errors(errors, field), do: Map.get(errors, field, [])

  defp preference_errors_from_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
