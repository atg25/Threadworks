defmodule ChatApp.Accounts.UserPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_preferences" do
    field(:sizes, :string, default: "[]")
    field(:brands, :string, default: "[]")
    field(:budget_min, ChatApp.Ecto.DecimalString)
    field(:budget_max, ChatApp.Ecto.DecimalString)
    field(:style_keywords, :string, default: "[]")

    belongs_to(:user, ChatApp.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [:user_id, :sizes, :brands, :budget_min, :budget_max, :style_keywords])
    |> validate_required([:user_id])
  end
end
