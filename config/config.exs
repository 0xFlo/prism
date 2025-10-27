# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :gsc_analytics, :scopes,
  user: [
    default: true,
    module: GscAnalytics.Auth.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: GscAnalytics.AuthFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :gsc_analytics,
  ecto_repos: [GscAnalytics.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :gsc_analytics, GscAnalyticsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GscAnalyticsWeb.ErrorHTML, json: GscAnalyticsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GscAnalytics.PubSub,
  live_view: [signing_salt: "ZULgaFBu"]

# Configure Swoosh mailer for authentication emails
config :gsc_analytics, GscAnalytics.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Configure Vault for encrypting OAuth tokens
config :gsc_analytics, GscAnalytics.Vault, ciphers: []

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  gsc_analytics: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  gsc_analytics: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Override Phoenix default (Jason) to use Elixir v1.18's built-in JSON module
config :phoenix, :json_library, JSON

# Configure Google Search Console accounts
config :gsc_analytics, :gsc_accounts, %{
  1 => %{
    name: "Primary (Scrapfly)",
    service_account_file: Path.expand("../priv/production-284316-43f352dd1cda.json", __DIR__),
    default_property: "sc-domain:scrapfly.io",
    enabled?: true
  },
  2 => %{
    name: "Alba Analytics",
    service_account_file: Path.expand("../priv/alba-analytics-475918-0087cc476b9a.json", __DIR__),
    default_property: System.get_env("GSC_ACCOUNT_2_PROPERTY"),
    enabled?: true
  }
}

# Configure sync behaviour
config :gsc_analytics, GscAnalytics.GSC.Sync,
  query_batch_pages: 32,
  query_scheduler_chunk_size: 32

# Configure Hammer rate limiter
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       # Keep data for 2 minutes
       expiry_ms: 60_000 * 2,
       # Clean up every minute
       cleanup_interval_ms: 60_000
     ]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
