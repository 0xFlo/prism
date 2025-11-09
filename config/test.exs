import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :gsc_analytics, GscAnalytics.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "gsc_analytics_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :gsc_analytics, GscAnalyticsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jjGEzHBYAFzfYymA8fi/LA1NbvJiQoobcwjn3qM3eLgnGjjiZJnMdFb8AjzbPpIo",
  server: false

# Mailer not used in this app

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Default Google OAuth credentials for tests (overridden by runtime env when present)
config :gsc_analytics, :google_oauth,
  client_id: "test-client",
  client_secret: "test-secret"

config :gsc_analytics, :start_authenticator, false

# Encryption key for OAuth tokens in tests
System.put_env("CLOAK_KEY", "ZzkKpsL01gl7QvRP1ThEmypkny/XrLaM/3FrfIjtNuA=")

# Oban test configuration - use manual testing mode
config :gsc_analytics, Oban, testing: :manual
