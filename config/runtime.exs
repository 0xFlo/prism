import Config

project_root = Path.expand("..", __DIR__)

# Auto-load environment variables from .env files
# Loads .env and environment-specific files like .env.dev, .env.prod, .env.test
# Uses Dotenvy to make local development seamless without manual `source .env` commands
env_files = [
  Path.join(project_root, ".env"),
  Path.join(project_root, ".env.#{config_env()}")
]

# Load variables from .env files and set them in System environment
# Dotenvy returns {:ok, map} but doesn't automatically set env vars, so we do it manually
case Dotenvy.source(env_files) do
  {:ok, vars} -> Enum.each(vars, fn {key, val} -> System.put_env(key, val) end)
  # Files don't exist, skip silently
  {:error, _} -> :ok
end

credentials_file =
  case System.get_env("GOOGLE_OAUTH_CREDENTIALS_FILE") do
    nil ->
      Path.wildcard(Path.join(project_root, "client_secret_*.json"))
      |> List.first()

    path ->
      case Path.type(path) do
        :absolute -> path
        _ -> Path.expand(path, project_root)
      end
  end

oauth_from_file =
  with file when is_binary(file) <- credentials_file,
       true <- File.exists?(file),
       {:ok, contents} <- File.read(file),
       {:ok, decoded} <- JSON.decode(contents),
       config when is_map(config) <-
         Map.get(decoded, "web") || Map.get(decoded, "installed"),
       client_id when is_binary(client_id) <- Map.get(config, "client_id"),
       client_secret when is_binary(client_secret) <- Map.get(config, "client_secret") do
    redirect_uri =
      case Map.get(config, "redirect_uris") do
        [first | _] when is_binary(first) -> first
        _ -> nil
      end

    %{client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri}
  else
    _ -> nil
  end

runtime_client_id =
  System.get_env("GOOGLE_OAUTH_CLIENT_ID") ||
    (oauth_from_file && oauth_from_file.client_id)

runtime_client_secret =
  System.get_env("GOOGLE_OAUTH_CLIENT_SECRET") ||
    (oauth_from_file && oauth_from_file.client_secret)

runtime_redirect_uri =
  System.get_env("GOOGLE_OAUTH_REDIRECT_URI") ||
    (oauth_from_file && oauth_from_file.redirect_uri)

if config_env() == :prod do
  runtime_client_id ||
    raise """
    environment variable GOOGLE_OAUTH_CLIENT_ID is missing.
    Set this to the OAuth client ID generated in Google Cloud Console.
    """

  runtime_client_secret ||
    raise """
    environment variable GOOGLE_OAUTH_CLIENT_SECRET is missing.
    Set this to the OAuth client secret generated in Google Cloud Console.
    """

  System.get_env("CLOAK_KEY") ||
    raise """
    environment variable CLOAK_KEY is missing.
    Generate one with: mix phx.gen.secret 32
    Store the Base64 value and keep it stable across deploys to preserve encrypted OAuth tokens.
    """
end

if runtime_client_id && runtime_client_secret do
  config :gsc_analytics, :google_oauth,
    client_id: runtime_client_id,
    client_secret: runtime_client_secret,
    redirect_uri: runtime_redirect_uri
end

# Configure Oban plugins dynamically based on auto-sync settings
# This allows enabling/disabling scheduled syncs via environment variables
config :gsc_analytics, Oban, plugins: GscAnalytics.Config.AutoSync.plugins()

# Log auto-sync configuration status on startup
GscAnalytics.Config.AutoSync.log_status!()

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
#     PHX_SERVER=true bin/gsc_analytics start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :gsc_analytics, GscAnalyticsWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :gsc_analytics, GscAnalytics.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    queue_target: String.to_integer(System.get_env("DB_QUEUE_TARGET") || "100"),
    queue_interval: String.to_integer(System.get_env("DB_QUEUE_INTERVAL") || "1000"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

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
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :gsc_analytics, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :gsc_analytics, GscAnalyticsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :gsc_analytics, GscAnalyticsWeb.Endpoint,
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
  #     config :gsc_analytics, GscAnalyticsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :gsc_analytics, GscAnalytics.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

# ScrapFly SERP API Configuration
# Available in all environments (dev, test, prod)
config :gsc_analytics,
  scrapfly_api_key: System.get_env("SCRAPFLY_API_KEY")

# Hammer rate limiter backend configuration for multi-node support
# Defaults to ETS (single-node), set HAMMER_BACKEND=postgres for distributed rate limiting
hammer_backend =
  case System.get_env("HAMMER_BACKEND") do
    "postgres" ->
      # Distributed rate limiting via Postgres for multi-node deployments
      {Hammer.Backend.Ecto,
       [
         repo: GscAnalytics.Repo,
         # Keep buckets for 2 minutes
         expiry_ms: 60_000 * 2,
         # Clean up every minute
         cleanup_interval_ms: 60_000
       ]}

    "redis" ->
      # Distributed rate limiting via Redis for multi-node deployments
      # Requires REDIS_URL environment variable
      redis_url = System.get_env("REDIS_URL") || "redis://localhost:6379"

      {Hammer.Backend.Redis,
       [
         redis_url: redis_url,
         # Keep buckets for 2 minutes
         expiry_ms: 60_000 * 2,
         # Clean up every minute
         cleanup_interval_ms: 60_000
       ]}

    _ ->
      # Default: ETS backend (single-node only, but fastest)
      {Hammer.Backend.ETS,
       [
         # Keep data for 2 minutes
         expiry_ms: 60_000 * 2,
         # Clean up every minute
         cleanup_interval_ms: 60_000
       ]}
  end

config :hammer, backend: hammer_backend

if config_env() != :test do
  max_concurrency =
    case System.get_env("GSC_MAX_CONCURRENCY") do
      nil -> 1
      value -> String.to_integer(value)
    end

  max_queue_size =
    case System.get_env("GSC_MAX_QUEUE_SIZE") do
      nil -> 1_000
      value -> String.to_integer(value)
    end

  max_in_flight =
    case System.get_env("GSC_MAX_IN_FLIGHT") do
      nil -> 10
      value -> String.to_integer(value)
    end

  config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
    max_concurrency: max_concurrency,
    max_queue_size: max_queue_size,
    max_in_flight: max_in_flight
end
