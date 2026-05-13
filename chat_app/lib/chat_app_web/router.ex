defmodule ChatAppWeb.Router do
  @moduledoc """
  single browser pipeline serving one route - `live "/", ChatLive, :index`.
  No `:api` scope is wired today. The `:browser` pipeline includes session
  fetch, CSRF protection, and secure-headers - all required for LiveView.
  """

  use ChatAppWeb, :router

  import ChatAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChatAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug :auth_basic_when_configured
  end

  scope "/", ChatAppWeb do
    pipe_through :browser

    live "/", ChatLive, :index
    get "/dev/product_card", DevController, :product_card

    if Mix.env() == :dev do
      get "/dev/demo-login", DevController, :demo_login
    end
  end

  def auth_basic_when_configured(conn, _opts) do
    user = Application.get_env(:chat_app, :basic_auth_user)
    pass = Application.get_env(:chat_app, :basic_auth_password)

    if is_binary(user) and is_binary(pass) and user != "" and pass != "" do
      Plug.BasicAuth.basic_auth(conn, username: user, password: pass)
    else
      conn
    end
  end

  ## Authentication routes

  scope "/", ChatAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{ChatAppWeb.UserAuth, :require_authenticated}] do
      live "/saved", Live.SavedLive
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", ChatAppWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{ChatAppWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
