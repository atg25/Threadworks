defmodule ChatAppWeb.Router do
  @moduledoc """
  single browser pipeline serving one route - `live "/", ChatLive, :index`.
  No `:api` scope is wired today. The `:browser` pipeline includes session
  fetch, CSRF protection, and secure-headers - all required for LiveView.
  """

  use ChatAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ChatAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", ChatAppWeb do
    pipe_through :browser

    live "/", ChatLive, :index
  end
end
