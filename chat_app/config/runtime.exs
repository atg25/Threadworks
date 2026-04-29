import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/chat_app start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :chat_app, ChatAppWeb.Endpoint, server: true
end

if config_env() != :test do
  config :chat_app, ChatAppWeb.Endpoint,
    http: [port: String.to_integer(System.get_env("PORT", "4000"))]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :chat_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :chat_app, ChatAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  database_path =
    System.get_env("DATABASE_PATH") ||
      raise "DATABASE_PATH is missing — point at a writable .db path."

  config :chat_app, ChatApp.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "5"))

  config :chat_app, :basic_auth_user, System.get_env("BASIC_AUTH_USER")
  config :chat_app, :basic_auth_password, System.get_env("BASIC_AUTH_PASSWORD")

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :chat_app, ChatAppWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :chat_app, ChatAppWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end

if config_env() == :prod do
  config :chat_app, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")
end

if config_env() == :dev do
  env_path = Path.expand("../.env", __DIR__)

  if File.exists?(env_path) do
    apply(Dotenvy, :source!, [[env_path, System.get_env()], [side_effect: &System.put_env/1]])
  end

  case System.get_env("OPENAI_API_KEY") do
    key when key in [nil, "", "sk-local-dev", "sk-REPLACE_ME"] ->
      fallback_key =
        if File.exists?(env_path) do
          env_path
          |> File.read!()
          |> String.split("\n")
          |> Enum.find_value(fn line ->
            case String.split(line, "=", parts: 2) do
              ["OPENAI_API_KEY", value] -> String.trim(value)
              _ -> nil
            end
          end)
        end

      case fallback_key do
        value when value in [nil, "", "sk-local-dev", "sk-REPLACE_ME"] ->
          raise """
          OPENAI_API_KEY is not set.

          For local development, copy .env.example to .env and fill in your key:

              cp .env.example .env
              # then edit .env

          See README.md → Setup for details.
          """

        value ->
          System.put_env("OPENAI_API_KEY", value)
          Application.put_env(:chat_app, :openai_api_key, value)
      end

    nil ->
      raise """
      OPENAI_API_KEY is not set.

      For local development, copy .env.example to .env and fill in your key:

          cp .env.example .env
          # then edit .env

      See README.md → Setup for details.
      """

    key ->
      Application.put_env(:chat_app, :openai_api_key, key)
  end
end
