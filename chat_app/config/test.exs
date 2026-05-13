import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :chat_app, ChatAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "LHGDU9SBpwS0vzz2HEFdQPzOV+LKx2MxJbVdhoXqckr7w0lvlAkmBwkN0qFu2IzM",
  server: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :chat_app, :openai_api_key, "sk-test-stub"
config :chat_app, :ebay_app_id, "test_app_id"
config :chat_app, :ebay_cert_id, "test_cert_id"
config :chat_app, :openai_module, ChatApp.OpenAI.Stub
config :chat_app, :hybrid_engine_module, ChatApp.Search.MockHybridEngine
config :chat_app, :style_advisor_module, ChatApp.AI.MockStyleAdvisor
config :chat_app, :req_options, plug: {Req.Test, ChatApp.OpenAI}
config :chat_app, :allow_hero_override, true
config :chat_app, :disable_rate_limit, false

config :chat_app, :scrape_queries, ["test query"]

config :chat_app, Oban, testing: :inline

config :chat_app, ChatApp.Repo,
  database: Path.expand("../priv/repo/chat_app_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5,
  busy_timeout: 5_000

config :wallaby,
  otp_app: :chat_app,
  driver: Wallaby.Chrome,
  js_logger: false,
  screenshot_on_failure: true,
  screenshot_dir: "test/screenshots",
  max_wait_time: 5000,
  chromedriver:
    (
      # Portable chromedriver / Chrome binary resolution.
      # Priority:
      #   1. Explicit env-var override — for CI or machines without Puppeteer.
      #   2. Puppeteer cache glob — finds any installed version automatically.
      #   3. PATH fallback — Wallaby uses "chromedriver" (system install).
      chromedriver_path =
        System.get_env("CHROMEDRIVER_PATH") ||
          Path.wildcard(
            Path.expand(
              "~/.cache/puppeteer/chromedriver/mac_arm-*/chromedriver-mac-arm64/chromedriver"
            )
          )
          |> List.last() ||
          "chromedriver"

      chrome_binary =
        System.get_env("CHROME_BINARY_PATH") ||
          Path.wildcard(
            Path.expand(
              "~/.cache/puppeteer/chrome/mac_arm-*/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
            )
          )
          |> List.last()

      base = [
        path: chromedriver_path,
        headless: true,
        args: ["--no-sandbox", "--disable-dev-shm-usage"]
      ]

      if chrome_binary, do: Keyword.put(base, :binary, chrome_binary), else: base
    )
