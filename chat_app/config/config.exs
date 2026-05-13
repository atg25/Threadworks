# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :chat_app, :scopes,
  user: [
    default: true,
    module: ChatApp.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ChatApp.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :chat_app,
  # Used by Ecto generators (mix phx.gen.schema, etc.) once Sprint 15's persistence layer lands.
  generators: [timestamp_type: :utc_datetime]

config :chat_app, ecto_repos: [ChatApp.Repo]

scrape_queries = [
  "vintage levi",
  "y2k denim",
  "silk slip dress",
  "90s windbreaker",
  "cashmere sweater"
]

config :chat_app, :scrape_queries, scrape_queries

config :chat_app, Oban,
  repo: ChatApp.Repo,
  queues: [scraper: 3, embedder: 5],
  notifier: Oban.Notifiers.PG,
  prefix: false,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */2 * * *", ChatApp.ETL.Workers.ScrapeWorker, args: %{"queries" => scrape_queries}}
     ]}
  ]

config :chat_app, :openai_model, "gpt-4o"

config :chat_app,
       :openai_embeddings_url,
       System.get_env("OPENAI_EMBEDDINGS_URL", "https://api.openai.com/v1/embeddings")

config :chat_app, :ebay_api_base_url, System.get_env("EBAY_API_BASE_URL", "https://api.ebay.com")

config :chat_app, :ebay_app_id, System.get_env("EBAY_APP_ID", "")
config :chat_app, :ebay_cert_id, System.get_env("EBAY_CERT_ID", "")

config :chat_app,
       :depop_api_base_url,
       System.get_env("DEPOP_API_BASE_URL", "https://api.depop.com")

config :chat_app, :poshmark_base_url, System.get_env("POSHMARK_BASE_URL", "https://poshmark.com")

config :hammer,
  backend:
    {Hammer.Backend.ETS, [expiry_ms: 1_000 * 60 * 60 * 4, cleanup_interval_ms: 1_000 * 60 * 10]}

# Configure the endpoint
config :chat_app, ChatAppWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: ChatAppWeb.ErrorHTML, json: ChatAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ChatApp.PubSub,
  live_view: [signing_salt: "NIcEdVtM"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  chat_app: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  chat_app: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :chat_app, ChatApp.Mailer, adapter: Swoosh.Adapters.Local

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
