defmodule ChatApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :chat_app,
      description: "A single-page streaming AI chat console built on Phoenix LiveView.",
      package: [
        licenses: ["MIT"],
        links: %{"GitHub" => "https://github.com/atg25/Threadworks"}
      ],
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {ChatApp.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:swoosh, "~> 1.4"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix, "~> 1.8.7"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:plug_cowboy, "~> 2.7"},
      {:req, "~> 0.5"},
      {:earmark, "~> 1.4"},
      {:jason, "~> 1.4"},
      {:hammer, "~> 6.2"},
      {:dotenvy, "~> 0.8", only: :dev},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:oban, "~> 2.17"},
      # Pinned exactly — native lib 0.1.5; smoke-tested 2026-05-11: MATCH syntax confirmed working
      {:sqlite_vec, "== 0.1.0"},
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.13"},
      {:dns_cluster, "~> 0.2.0"},
      {:gettext, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:ex_doc, "~> 0.31", only: [:dev, :test], runtime: false},
      {:floki, ">= 0.30.0"},
      {:bypass, github: "PSPDFKit-labs/bypass", only: :test},
      {:wallaby, "~> 0.30", runtime: false, only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate", "assets.setup", "assets.build"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind chat_app", "esbuild chat_app"],
      "assets.deploy": [
        "tailwind chat_app --minify",
        "esbuild chat_app --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "test",
        "cmd --cd assets npm test"
      ]
    ]
  end
end
