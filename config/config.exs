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

config :req, :default_options,
  finch: GscAnalytics.Finch,
  pool_timeout: 5_000,
  receive_timeout: 15_000

config :gsc_analytics, :http_client, GscAnalytics.HTTPClient.Req

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  gsc_analytics: [
    args:
      ~w(js/app.jsx --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --loader:.js=jsx --loader:.jsx=jsx --alias:@=. --alias:phoenix-colocated=../_build/dev/phoenix-colocated),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
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

# Google Search Console accounts are now managed in the database via workspaces table
# Users can add/remove workspaces through the Settings UI

# Configure sync behaviour
config :gsc_analytics, GscAnalytics.GSC.Sync,
  query_batch_pages: 32,
  query_scheduler_chunk_size: 32

# Note: Hammer rate limiter backend is configured at runtime in config/runtime.exs
# This allows switching between ETS (single-node) and Postgres/Redis (multi-node) via HAMMER_BACKEND env var

# Configure Oban for background job processing
# Note: Plugins and cron configuration are managed at runtime via GscAnalytics.Config.AutoSync
config :gsc_analytics, Oban,
  repo: GscAnalytics.Repo,
  # Base plugins that run in all environments
  plugins: [
    # Prune completed jobs after 7 days
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Cron scheduler for recurring jobs
    {Oban.Plugins.Cron,
     crontab: [
       # Prune old SERP snapshots daily at 2 AM
       {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker}
     ]}
  ],
  queues: [
    default: 10,
    # GSC sync runs one job at a time to avoid rate limits
    gsc_sync: 1,
    # SERP position checks (3 concurrent)
    serp_check: 3,
    # HTTP status checks (10 concurrent for high throughput)
    http_checks: 10,
    # Maintenance tasks (1 at a time)
    maintenance: 1
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
