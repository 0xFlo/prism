# Environment-Based Configuration in Phoenix Applications

**Research Date:** 2025-11-08
**Focus Areas:** Phoenix 1.7+ configuration, 12-factor app principles, Elixir config libraries, feature flags, testing strategies

---

## Table of Contents

1. [Phoenix 1.7+ Configuration](#phoenix-17-configuration)
2. [12-Factor App Principles](#12-factor-app-principles)
3. [Elixir Configuration Libraries](#elixir-configuration-libraries)
4. [Feature Flags & Runtime Toggles](#feature-flags--runtime-toggles)
5. [Testing with Different Configs](#testing-with-different-configs)
6. [Best Practices Summary](#best-practices-summary)
7. [References](#references)

---

## Phoenix 1.7+ Configuration

### config/runtime.exs vs config/config.exs

**Compile-Time Configuration (config/config.exs)**

- **When Evaluated:** Loaded whenever you invoke a mix command, evaluated during code compilation or release assembly
- **Persistence:** Configuration is baked into the compiled code and cannot change after compilation
- **Use Cases:** Static configuration that doesn't vary between environments (build tools, logger format, compile-time settings)
- **Key Limitation:** Requires recompilation when values change, adding friction to development workflows

**Runtime Configuration (config/runtime.exs)**

- **When Evaluated:** Executed early in the boot process (after Elixir and Erlang's main applications start, before your app starts)
- **Flexibility:** Can change after building a release with `mix release`, works in all environments (dev, test, prod)
- **Use Cases:** Environment-specific settings, secrets, database URLs, API keys, anything that varies between deployments
- **System Restart:** After providers execute, the Erlang system restarts with new configuration

**Source:** [Phoenix GitHub - runtime.exs template](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_single/config/runtime.exs)

### Key Rules for runtime.exs

1. **MUST** import `Config` at the top
2. **MUST NOT** import any other configuration file via `import_config`
3. **MUST NOT** access `Mix` in any way (Mix is not available in releases)
4. **Environment Wrapping:** Production configs typically wrapped in `if config_env() == :prod do`

**Source:** [Elixir Configuration Best Practices](https://dev.to/manhvanvu/elixir-configuration-environment-variables-4j1f)

### Best Practices for 2024

**Priority Order:**

1. **Prefer runtime configuration** - Move as much as possible to `config/runtime.exs`
2. **Use System.fetch_env!/1** - Fail fast if required environment variables are missing
3. **Avoid compile-time ENV reads** - Using `System.get_env/1` in compile-time config bakes values into releases
4. **Single source of truth** - If a variable is in `runtime.exs`, it MUST NOT be in compile-time configs

**Source:** [Tips for improving your Elixir configuration - Felt Blog](https://felt.com/blog/elixir-configuration)

### Environment Variables: fetch_env! vs get_env

```elixir
# ✅ Recommended for required variables - fails fast at startup
config :my_app, MyApp.Endpoint,
  http: [port: System.fetch_env!("PORT")]

# ❌ Avoid - returns nil, fails later at runtime
config :my_app, MyApp.Endpoint,
  http: [port: System.get_env("PORT")]

# ✅ Acceptable with meaningful defaults that work in production
config :my_app, MyApp.Endpoint,
  http: [port: System.get_env("PORT", "4000")]
```

**Why fetch_env!/1?** "It is best to fail early" rather than deploy with missing configuration that causes runtime failures later.

**Source:** [Elixir Config and Environment Variables - StakNine](https://staknine.com/elixir-config-environment-variables/)

### Organizing Configuration Files

**Traditional Phoenix Approach (Environment-Based):**
```
config/
├── config.exs
├── dev.exs
├── test.exs
├── prod.exs
└── runtime.exs
```

**Alternative: Topic-Based Organization**
```
config/
├── config.exs (imports all topic files)
├── runtime.exs
└── config/
    ├── endpoint.exs
    ├── logger.exs
    ├── oban.exs
    ├── repo.exs
    └── ...
```

**Benefits of Topic-Based:**
- "Discovering or editing a config variable now requires opening only one file instead of four"
- Keeps files concise and focused
- Aligns with developer workflow (editing related configs across environments together)

**Source:** [Configuring Phoenix apps: Two small adjustments - bitcrowd](https://bitcrowd.dev/two-small-adjustments-of-phoenix-application-configuration/)

### Config Providers

**Overview:** Config providers are used during releases to load external configuration while the system boots.

**Built-in Provider:**
```elixir
# In mix.exs releases section
releases: [
  demo: [
    config_providers: [
      {Config.Reader, {:system, "RELEASE_ROOT", "/extra_config.exs"}}
    ]
  ]
]
```

**Custom Provider Implementation:**

```elixir
defmodule JSONConfigProvider do
  @behaviour Config.Provider

  @impl true
  def init(path) when is_binary(path), do: path

  @impl true
  def load(config, path) do
    {:ok, _} = Application.ensure_all_started(:jason)
    json = path |> File.read!() |> Jason.decode!()

    Config.Reader.merge(config,
      my_app: [
        some_value: json["some_value"]
      ]
    )
  end
end
```

**Key Callbacks:**

1. **`init/1`** - Validates arguments and prepares state (runs on build machine)
2. **`load/2`** - Loads configuration at runtime (runs on target machine)

**State Requirements:** Must contain only serializable data (integers, strings, atoms, tuples, maps, lists) - NO PIDs, references, or functions.

**Source:** [Config.Provider Documentation](https://hexdocs.pm/elixir/Config.Provider.html)

---

## 12-Factor App Principles

### III. Config - Store config in the environment

**Core Principle:** "Config varies substantially across deploys, code does not." Configuration must be strictly separated from code.

**What is Config?**
- Database, caching, and other backing service handles
- Credentials for external services (AWS S3, Twitter API, etc.)
- Deploy-specific values (canonical hostname, port numbers)

**What is NOT Config?**
- Internal application config (routing files, dependency injection wiring)
- This should stay in code as it doesn't vary between deploys

**Source:** [The Twelve-Factor App - Config](https://12factor.net/config)

### Why Environment Variables?

**Advantages:**
1. **Language/OS agnostic** - Standard across all platforms
2. **Easy to change** - No code changes or recompilation needed
3. **Hard to commit accidentally** - Unlike config files
4. **No custom mechanisms** - No framework-specific config systems

**Anti-Patterns to Avoid:**
- ❌ Hard-coded constants in code (risk exposing credentials)
- ❌ Config files in version control (prone to accidental commits)
- ❌ Named "environments" (development, staging, production) that group configs

### Scaling Configuration

**Problem with Named Environments:**
As deployments multiply (staging, QA, production-US, production-EU, etc.), named environments create "combinatorial explosion of config" making management unwieldy.

**Solution:**
Treat each environment variable as an **independent, orthogonal control** managed separately per deployment. This scales cleanly as applications naturally expand.

**Source:** [The Twelve-Factor App - Config](https://12factor.net/config)

### Elixir/Phoenix 12-Factor Implementation

**Modern Phoenix (1.6+):**
```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  database_url = System.fetch_env!("DATABASE_URL")

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))
end
```

**Why This Works:**
- All environment variables loaded at runtime
- Same compiled artifact deploys to all environments
- Environment variables control behavior per deployment
- Fails fast if required variables missing

**Source:** [Making 12factor Elixir/Phoenix releases](https://nts.strzibny.name/12factor-elixir-phoenix-releases/)

---

## Elixir Configuration Libraries

### Built-in: Application.get_env

**Basic Usage:**
```elixir
# Set in config files
config :my_app, :some_key, "value"

# Retrieve in code
Application.get_env(:my_app, :some_key)
Application.fetch_env!(:my_app, :some_key)  # Raises if not found
```

**Limitations:**
- Encourages scattered configuration reads throughout codebase
- Hard to track what configuration is actually used
- Couples modules to global application environment
- Makes testing harder (requires Application.put_env mocking)

**Source:** [System.get_env vs. Application.get_env - Elixir Forum](https://elixirforum.com/t/system-get-env-vs-application-get-env/11246)

### Vapor - Runtime Configuration System

**GitHub:** [keathley/vapor](https://github.com/keathley/vapor)

**Purpose:** "Runtime configuration system for Elixir" that loads dynamic configuration from multiple sources with validation.

**Key Features:**
- Multiple configuration providers (ENV vars, files, Dotenv)
- Supports JSON, YAML, TOML file formats
- Configuration validation with required fields
- Type casting/transformation via `:map` option
- Default values for optional settings

**Installation:**
```elixir
# mix.exs
{:vapor, "~> 0.10.0"}
```

**Basic Usage:**
```elixir
defmodule MyApp.Application do
  def start(_type, _args) do
    config = Vapor.load!([
      %Vapor.Provider.Env{
        bindings: [
          {:port, "PORT", required: true, map: &String.to_integer/1},
          {:db_url, "DATABASE_URL", required: true},
          {:pool_size, "POOL_SIZE", default: 10, map: &String.to_integer/1}
        ]
      }
    ])

    # Pass config to children as arguments
    children = [
      {MyApp.Endpoint, config},
      {MyApp.Repo, config}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Configuration Options:**
- **`:required`** - Defaults to `true`, raises exception if missing and no default
- **`:map`** - Transform function for type casting/validation
- **`:default`** - Fallback value (skips transformations)

**Provider Precedence:**
Providers merge in order specified - later providers override earlier ones. This enables layering from general to specific.

**Plan-Based Architecture:**
```elixir
defmodule MyApp.Config do
  use Vapor.Planner

  dotenv()

  config :database, env([
    {:url, "DATABASE_URL"},
    {:pool_size, "POOL_SIZE", default: 10, map: &String.to_integer/1}
  ])

  config :endpoint, env([
    {:port, "PORT", map: &String.to_integer/1},
    {:secret_key_base, "SECRET_KEY_BASE"}
  ])
end

# Load configuration
config = Vapor.load!(MyApp.Config)
```

**Best Practice:** "All of our children processes should be configurable by passing arguments to them. We shouldn't couple them to any global configuration system."

**Sources:**
- [Vapor Documentation](https://hexdocs.pm/vapor/Vapor.html)
- [Configuring your Elixir Application at Runtime with Vapor - AppSignal](https://blog.appsignal.com/2020/04/28/configuring-your-elixir-application-at-runtime-with-vapor.html)
- [Runtime Configuration in Elixir Apps - Keathley.io](https://keathley.io/blog/vapor-and-configuration.html)

### Dotenvy - .env File Support

**HexDocs:** [dotenvy](https://hexdocs.pm/dotenvy/)

**Purpose:** "Lets you easily read 'dotenv' files (e.g., `.env`) into your runtime configuration" and sets system environment variables.

**Installation:**
```elixir
# mix.exs
{:dotenvy, "~> 1.1.0"}
```

**Phoenix Integration:**

**Option 1: Generate New App**
```bash
# Install generator
mix archive.install hex dotenvy_generators

# Generate Phoenix app with Dotenvy
mix phx.new.dotenvy my_app
```

**Option 2: Retrofit Existing App**

1. Create `envs/` directory with files:
   - `.env` - Shared defaults
   - `.dev.env` - Development overrides
   - `.test.env` - Test environment
   - `.prod.env` - Production settings

2. Update `config/runtime.exs`:
```elixir
import Config
import Dotenvy

# Development/test: read from envs/ directory
# Production: read from RELEASE_ROOT
env_dir = if config_env() == :prod do
  System.get_env("RELEASE_ROOT", "")
else
  Path.absname("envs", __DIR__)
end

source!([
  Path.join(env_dir, ".env"),
  Path.join(env_dir, ".#{config_env()}.env"),
  Path.join(env_dir, ".#{config_env()}.overrides.env")
])

# Now environment variables are set, use them in config
config :my_app, MyApp.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]
```

**File Precedence:**
Files loaded in order, later files override earlier ones:
1. `.env` - Base defaults
2. `.{env}.env` - Environment-specific (dev, test, prod)
3. `.{env}.overrides.env` - Local overrides (gitignored)

**Guiding Principle:** "Use runtime configuration whenever possible" to enable faster development and flexible deployments.

**Sources:**
- [Dotenvy Documentation](https://hexdocs.pm/dotenvy/)
- [Configuration in Elixir with Dotenvy - Medium](https://fireproofsocks.medium.com/configuration-in-elixir-with-dotenvy-8b20f227fc0e)
- [Using Dotenvy with Phoenix](https://hexdocs.pm/dotenvy/phoenix.html)

### NimbleOptions - Configuration Validation

**GitHub:** [dashbitco/nimble_options](https://github.com/dashbitco/nimble_options)

**Purpose:** "A tiny library for validating and documenting high-level options" using keyword list schemas.

**Installation:**
```elixir
{:nimble_options, "~> 1.1"}
```

**Key Features:**
- Schema-based validation for keyword lists
- Type checking with extensive type system
- Automatic documentation generation
- Nested schema support
- Custom validation functions

**Basic Usage:**
```elixir
defmodule MyApp.Worker do
  @schema NimbleOptions.new!(
    name: [type: :string, required: true, doc: "Worker name"],
    concurrency: [type: :pos_integer, default: 5, doc: "Max concurrent tasks"],
    timeout: [type: :timeout, default: :infinity, doc: "Task timeout"],
    retry: [
      type: :keyword_list,
      keys: [
        max_attempts: [type: :pos_integer, default: 3],
        backoff: [type: {:in, [:exponential, :linear]}, default: :exponential]
      ]
    ]
  )

  def start_link(opts) do
    # Validate options against schema
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @schema) do
      GenServer.start_link(__MODULE__, validated_opts)
    end
  end
end
```

**Supported Types:**
- **Basic:** `:any`, `:keyword_list`, `:atom`, `:string`, `:boolean`, `:integer`, `:float`
- **Specialized:** `:timeout`, `:pid`, `:reference`, `:mfa`, `:mod_arg`
- **Collections:** `{:list, subtype}`, `{:tuple, [subtypes]}`, `:map`
- **Advanced:** `{:custom, mod, fun, args}`, `{:or, subtypes}`, `{:in, choices}`, `{:struct, struct_name}`

**Schema Options:**
- **`:type`** - Data type (defaults to `:any`)
- **`:required`** - Boolean indicating if option must be provided
- **`:default`** - Default value if omitted (validated against type)
- **`:keys`** - For keyword_list/map types, defines nested schema
- **`:deprecated`** - Warning message for deprecated options
- **`:doc`** - Documentation string
- **`:type_spec`** - Custom typespec (v1.1.0+)

**Documentation Generation:**
```elixir
IO.puts(NimbleOptions.docs(@schema))
```

**Benefits:**
- "Single unified approach to defining static options"
- Catches configuration errors at function call time
- Self-documenting through schema definitions
- Nested validation with clear error paths

**Sources:**
- [NimbleOptions Documentation](https://hexdocs.pm/nimble_options/NimbleOptions.html)
- [Validating Data in Elixir: Using Ecto and NimbleOptions - AppSignal](https://blog.appsignal.com/2023/11/07/validating-data-in-elixir-using-ecto-and-nimbleoptions.html)

---

## Feature Flags & Runtime Toggles

### Overview

**Definition:** Feature flags (also known as feature toggles or feature switches) are "a software development technique that controls functionality during runtime, without deploying new code."

**Use Cases:**
- Enable/disable features without deployment
- Test features internally before public release
- A/B testing and gradual rollouts
- Quick rollback if features cause problems
- Canary deployments

**Source:** [Feature Toggles - Martin Fowler](https://martinfowler.com/articles/feature-toggles.html)

### FunWithFlags - Elixir Feature Flag Library

**GitHub:** [tompave/fun_with_flags](https://github.com/tompave/fun_with_flags)

**Purpose:** OTP application providing "granular and precise control over which feature should be enabled or disabled for which type of structs."

**Installation:**
```elixir
# mix.exs
{:fun_with_flags, "~> 1.10"},
{:fun_with_flags_ui, "~> 0.8"}  # Optional web dashboard
```

**Configuration:**
```elixir
# config/config.exs
config :fun_with_flags, :cache,
  enabled: true,
  ttl: 900  # 15 minutes

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: MyApp.PubSub

config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: MyApp.Repo
```

**Database Migration:**
```elixir
defmodule MyApp.Repo.Migrations.CreateFeatureFlagsTable do
  use Ecto.Migration

  def change do
    create table(:fun_with_flags_toggles, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end

    create index(
      :fun_with_flags_toggles,
      [:flag_name, :gate_type, :target],
      unique: true,
      name: "fwf_flag_name_gate_target_idx"
    )
  end
end
```

**Router Setup (Web Dashboard):**
```elixir
# router.ex
scope "/admin" do
  pipe_through :browser
  forward "/feature-flags", FunWithFlags.UI.Router, namespace: "feature-flags"
end
```

**Architecture:**
- **Persistent Storage:** PostgreSQL, MySQL, or SQLite via Ecto (or Redis)
- **Local Cache:** ETS tables for fast lookups
- **Synchronization:** PubSub notifications for cache invalidation across nodes

**Sources:**
- [FunWithFlags GitHub](https://github.com/tompave/fun_with_flags)
- [How to Add Feature Flags in Phoenix - DockYard](https://dockyard.com/blog/2023/02/28/how-to-add-feature-flags-in-a-phoenix-application-using-fun_with_flags)

### Gate Types

**1. Boolean Gate - Global On/Off**
```elixir
# Enable for everyone
FunWithFlags.enable(:new_dashboard)

# Check in code
if FunWithFlags.enabled?(:new_dashboard) do
  render("new_dashboard.html")
else
  render("old_dashboard.html")
end
```

**2. Actor Gate - Specific Entities**

Requires implementing the `FunWithFlags.Actor` protocol:

```elixir
defimpl FunWithFlags.Actor, for: MyApp.Accounts.User do
  def id(%{id: id}), do: "user:#{id}"
end

# Enable for specific user
user = Accounts.get_user!(123)
FunWithFlags.enable(:new_dashboard, for_actor: user)

# Check with actor context
FunWithFlags.enabled?(:new_dashboard, for: user)
```

**3. Group Gate - Categories of Entities**

Implement the `FunWithFlags.Group` protocol:

```elixir
defimpl FunWithFlags.Group, for: MyApp.Accounts.User do
  def in?(%{role: :admin}, "admins"), do: true
  def in?(%{beta_tester: true}, "beta_testers"), do: true
  def in?(_, _), do: false
end

# Enable for group
FunWithFlags.enable(:experimental_feature, for_group: "beta_testers")

# Check group membership
FunWithFlags.enabled?(:experimental_feature, for: user)
```

**4. Percentage of Time Gate - Pseudo-Random**

"Useful to gradually introduce alternative code paths" with randomness.

```elixir
# Enable 25% of the time (random)
FunWithFlags.enable(:ab_test_variant, for_percentage_of: {:time, 0.25})
```

**5. Percentage of Actors Gate - Deterministic**

Enables feature for a percentage of actors using "SHA256 hashing" of actor ID + flag name for repeatable results.

```elixir
# Enable for 10% of users (deterministic based on user ID)
FunWithFlags.enable(:new_feature, for_percentage_of: {:actors, 0.10})

# Same user always gets same result
FunWithFlags.enabled?(:new_feature, for: user)  # Consistent per user
```

**Gate Priority Order:**

"Actors > Groups > Boolean > Percentage" - Most specific gates override less specific ones.

**Example:**
```elixir
# Global: disabled for everyone
FunWithFlags.disable(:feature)

# Group: enabled for admins
FunWithFlags.enable(:feature, for_group: "admins")

# Actor: disabled for specific admin user
FunWithFlags.disable(:feature, for_actor: specific_admin)

# Result: specific_admin cannot access (actor gate wins)
# Other admins can access (group gate)
# Regular users cannot access (boolean gate)
```

**Source:** [FunWithFlags GitHub](https://github.com/tompave/fun_with_flags)

### Gradual Rollout & Canary Deployments

**Canary Deployment Pattern:**

"Making small, staged releases that allows you to test new changes or features to a subset of users or servers."

**Typical Rollout Strategy:**
1. Deploy to 1% of users
2. Monitor metrics (errors, performance)
3. Increase to 5% if stable
4. Increase to 10%
5. Gradually increase to 25%, 50%, 75%
6. Roll out to 100%

**Feature Flags for Canary:**

"The new version is deployed to all production machines, but the new features are hidden behind feature flags that limit exposure to a targeted subset."

**Benefits:**
- Instant rollback by disabling flag (no deployment needed)
- Target specific user segments
- Combine with monitoring/metrics
- Automate percentage increases

**Implementation with FunWithFlags:**

```elixir
# Week 1: Internal testing only
FunWithFlags.enable(:new_checkout, for_group: "employees")

# Week 2: Beta testers (5% of users)
FunWithFlags.enable(:new_checkout, for_percentage_of: {:actors, 0.05})

# Week 3: Increase to 25%
FunWithFlags.enable(:new_checkout, for_percentage_of: {:actors, 0.25})

# Week 4: Increase to 50%
FunWithFlags.enable(:new_checkout, for_percentage_of: {:actors, 0.50})

# Week 5: Full rollout
FunWithFlags.enable(:new_checkout)

# Emergency: Instant rollback
FunWithFlags.disable(:new_checkout)
```

**Sources:**
- [Canary Deployment with Feature Flags - Unleash](https://www.getunleash.io/blog/canary-deployment-what-is-it)
- [Understanding Canary Releases and Feature Flags - Harness](https://www.harness.io/blog/canary-release-feature-flags)

### A/B Testing with Feature Flags

**Experiment Toggles:**

"Used to perform multivariate or A/B testing, where each user is placed into a cohort and the Toggle Router will consistently send a given user down one codepath or another."

**Implementation Pattern:**

```elixir
defmodule MyAppWeb.ProductController do
  def show(conn, %{"id" => id}) do
    product = Products.get_product!(id)
    user = conn.assigns.current_user

    # Consistent cohort assignment per user
    template = if FunWithFlags.enabled?(:new_product_page, for: user) do
      "product_new.html"
    else
      "product_old.html"
    end

    render(conn, template, product: product)
  end
end
```

**Tracking Results:**

```elixir
# Log variant exposure for analytics
def track_variant(user, flag_name) do
  variant = if FunWithFlags.enabled?(flag_name, for: user) do
    "variant_b"
  else
    "variant_a"
  end

  Analytics.track(user.id, "experiment_exposure", %{
    experiment: flag_name,
    variant: variant
  })
end
```

**Source:** [Feature Toggles - Martin Fowler](https://martinfowler.com/articles/feature-toggles.html)

### Simple Feature Flag System (Without Library)

For basic needs, build a simple system without external dependencies:

```elixir
# config/runtime.exs
config :my_app, :feature_flags, %{
  new_dashboard: System.get_env("FEATURE_NEW_DASHBOARD", "false") == "true",
  beta_api: System.get_env("FEATURE_BETA_API", "false") == "true"
}

# lib/my_app/feature_flags.ex
defmodule MyApp.FeatureFlags do
  def enabled?(flag_name) do
    flags = Application.get_env(:my_app, :feature_flags, %{})
    Map.get(flags, flag_name, false)
  end
end

# Usage
if MyApp.FeatureFlags.enabled?(:new_dashboard) do
  # New code path
end
```

**When to Use:**
- Simple boolean flags only
- Small team/application
- No need for user-specific targeting
- No web dashboard requirement

**When to Use Library:**
- User-specific targeting needed
- Percentage-based rollouts
- Web dashboard for non-technical users
- A/B testing requirements

**Source:** [How to build the simplest feature flag system in Elixir & Phoenix apps](https://www.chriis.dev/opinion/how-to-build-the-simplest-feature-flag-system-in-elixir-and-phoenix-apps)

---

## Testing with Different Configs

### Test Environment Configuration

**config/test.exs:**
```elixir
import Config

config :my_app, MyApp.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :my_app, MyApp.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key",
  server: false

config :logger, level: :warning
```

**Test Partitioning for CI:**

ExUnit supports partitioning tests across multiple CI workers:

```elixir
# Database per partition
database: "my_app_test#{System.get_env("MIX_TEST_PARTITION")}"
```

**CI Configuration (GitHub Actions):**
```yaml
strategy:
  matrix:
    partition: [1, 2, 3, 4]
env:
  MIX_TEST_PARTITION: ${{ matrix.partition }}
```

**Source:** [Improving Testing & CI in Phoenix - Phoenix Blog](https://www.phoenixframework.org/blog/improving-testing-and-continuous-integration-in-phoenix)

### Mocking Environment Variables in Tests

**Method 1: Application.put_env**

```elixir
defmodule MyApp.ConfigTest do
  use ExUnit.Case

  setup do
    # Save original config
    original = Application.get_all_env(:my_app)

    # Set test config
    Application.put_env(:my_app, MyModule, [
      api_key: "test_key",
      endpoint: "http://test.example.com"
    ])

    # Restore on exit
    on_exit(fn ->
      Application.put_all_env([{:my_app, original}])
    end)

    :ok
  end

  test "uses test configuration" do
    config = Application.get_env(:my_app, MyModule)
    assert config[:api_key] == "test_key"
  end
end
```

**Important Caveat:** "This method will set _all_ configuration values for the module, so make sure to pass in all environment variables needed for your test."

**Source:** [Testing Environment Variables in Elixir/Phoenix - Sean Lawrence](https://www.sean-lawrence.com/testing-environment-variables-in-an-elixir-phoenix-application/)

### Mocking with Behaviors

**Pattern:** Use behaviors to swap implementations based on environment.

```elixir
# Define behavior
defmodule MyApp.PaymentProcessor do
  @callback charge(amount :: integer, token :: String.t()) ::
    {:ok, String.t()} | {:error, String.t()}
end

# Production implementation
defmodule MyApp.PaymentProcessor.Stripe do
  @behaviour MyApp.PaymentProcessor

  def charge(amount, token) do
    # Real Stripe API call
  end
end

# Test implementation
defmodule MyApp.PaymentProcessor.Mock do
  @behaviour MyApp.PaymentProcessor

  def charge(amount, _token) when amount > 0 do
    {:ok, "mock_charge_id_#{:rand.uniform(1000)}"}
  end

  def charge(_amount, _token) do
    {:error, "invalid_amount"}
  end
end

# config/config.exs
config :my_app, :payment_processor, MyApp.PaymentProcessor.Stripe

# config/test.exs
config :my_app, :payment_processor, MyApp.PaymentProcessor.Mock

# Usage in code
defmodule MyApp.Orders do
  def process_payment(order) do
    processor = Application.get_env(:my_app, :payment_processor)
    processor.charge(order.total, order.payment_token)
  end
end
```

**Benefits:**
- No external API calls in tests
- Fast test execution
- Predictable test behavior
- Easy to simulate error conditions

**Source:** [Mocks in Elixir/Phoenix using Behaviors - Medium](https://brooklinmyers.medium.com/mocks-in-elixir-phoenix-using-behaviors-and-environment-variables-7e41dfd749ae)

### Better Pattern: Dependency Injection

**Anti-Pattern:**
```elixir
defmodule MyApp.Service do
  def call do
    # Tightly coupled to Application config
    processor = Application.get_env(:my_app, :payment_processor)
    processor.charge(100, "token")
  end
end
```

**Recommended:**
```elixir
defmodule MyApp.Service do
  # Accept dependency as argument
  def call(payment_processor \\ default_processor()) do
    payment_processor.charge(100, "token")
  end

  defp default_processor do
    Application.get_env(:my_app, :payment_processor)
  end
end

# Test with explicit dependency
test "processes payment" do
  result = MyApp.Service.call(MyApp.PaymentProcessor.Mock)
  assert {:ok, _charge_id} = result
end
```

**Benefits:**
- No Application.put_env needed
- Explicit dependencies
- Supports async tests
- Easier to reason about

### CI/CD Environment Variables

**GitLab CI Example:**

```yaml
# .gitlab-ci.yml
test:
  stage: test
  services:
    - postgres:14
  variables:
    POSTGRES_DB: my_app_test
    POSTGRES_HOST: postgres
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    MIX_ENV: test
  script:
    - mix deps.get
    - mix ecto.create
    - mix ecto.migrate
    - mix test
```

**Dynamic Configuration:**
```elixir
# config/test.exs
config :my_app, MyApp.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "my_app_test")
```

**Source:** [Setting up Phoenix CI/CD on GitLab](https://experimentingwithcode.com/setting-up-a-phoenix-ci-cd-pipeline-on-gitlab-part-1/)

---

## Best Practices Summary

### Configuration Management

1. **Prefer Runtime over Compile-Time**
   - Move maximum configuration to `config/runtime.exs`
   - Only use compile-time config for truly static values
   - Avoid `System.get_env` in `config/config.exs`

2. **Use System.fetch_env!/1 for Required Variables**
   - Fail fast at startup if required config missing
   - Better than `System.get_env/1` which fails later at runtime
   - Use `System.get_env/2` only with production-safe defaults

3. **Single Source of Truth**
   - If variable in `runtime.exs`, remove from compile-time configs
   - Eliminates confusion about which value is actually used
   - Prevents compile-time vs runtime conflicts

4. **Organize by Topic, Not Environment**
   - Consider topic-based config files (endpoint.exs, repo.exs, etc.)
   - Reduces file switching when editing related settings
   - Keeps configuration files focused and manageable

5. **Never Commit Secrets**
   - Use environment variables in production
   - Use `.env` files (gitignored) in development
   - Use secret management systems (Vault, AWS Secrets Manager)
   - Rotate secrets regularly with `mix phx.gen.secret`

### Configuration Libraries

6. **Choose the Right Tool**
   - **Simple apps:** Built-in config system + `System.fetch_env!/1`
   - **Complex validation:** Vapor or NimbleOptions
   - **Local development:** Dotenvy for `.env` support
   - **Custom sources:** Implement Config.Provider

7. **Pass Config as Arguments**
   - Avoid coupling processes to Application env
   - Pass configuration to GenServers/supervisors as arguments
   - Makes processes reusable and testable
   - Example: `{MyWorker, [config: config]}`

8. **Validate Configuration Early**
   - Use Vapor, NimbleOptions, or custom validation
   - Fail at startup, not during runtime
   - Provide clear error messages for missing/invalid config

### Feature Flags

9. **Start Simple, Scale as Needed**
   - Begin with environment variable toggles
   - Add FunWithFlags when targeting/rollouts needed
   - Use web dashboard for non-technical stakeholders

10. **Gradual Rollouts**
    - Start with internal users (group gates)
    - Increase percentage gradually (1% → 5% → 25% → 50% → 100%)
    - Monitor metrics at each stage
    - Keep rollback option (disable flag) ready

11. **Clean Up Old Flags**
    - Remove flags after full rollout
    - Document flag purpose and rollout plan
    - Set expiration dates for experiment flags

### Testing

12. **Minimize Configuration in Tests**
    - Use dependency injection over Application.put_env
    - Enables async tests (faster test suite)
    - Makes dependencies explicit
    - Easier to reason about behavior

13. **Use Behaviors for Mocking**
    - Define behavior contracts
    - Swap implementations via config
    - No runtime overhead in production
    - Type-safe with Dialyzer

14. **Test-Specific Configuration**
    - Keep test config minimal
    - Use test database per partition for CI
    - Set sensible defaults
    - Override only what's necessary

### General Principles

15. **Follow 12-Factor App Config**
    - Store config in environment variables
    - Treat config as orthogonal to code
    - Same build artifact for all environments
    - Language/OS agnostic configuration

16. **Keep Config Files Simple**
    - Avoid complex logic in config scripts
    - No module references or MFAs if possible
    - Centralize environment variable reads
    - Document required variables

17. **Documentation**
    - Document all required environment variables
    - Provide example `.env.example` file
    - List default values
    - Explain configuration options

---

## References

### Phoenix Documentation
- [Phoenix GitHub - runtime.exs template](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_single/config/runtime.exs)
- [Phoenix GitHub - config.exs template](https://github.com/phoenixframework/phoenix/blob/main/installer/templates/phx_single/config/config.exs)
- [Introduction to Deployment - Phoenix v1.8.1](https://hexdocs.pm/phoenix/deployment.html)

### Elixir Documentation
- [Config.Provider - Elixir](https://hexdocs.pm/elixir/Config.Provider.html)
- [Application - Elixir](https://github.com/elixir-lang/elixir/blob/main/lib/elixir/lib/application.ex)

### Blog Posts & Articles
- [Tips for improving your Elixir configuration - Felt](https://felt.com/blog/elixir-configuration)
- [Configuring Phoenix apps: Two small adjustments - bitcrowd](https://bitcrowd.dev/two-small-adjustments-of-phoenix-application-configuration/)
- [Elixir Configuration & Environment variables - DEV](https://dev.to/manhvanvu/elixir-configuration-environment-variables-4j1f)
- [Elixir Config and Environment Variables - StakNine](https://staknine.com/elixir-config-environment-variables/)
- [Making 12factor Elixir/Phoenix releases](https://nts.strzibny.name/12factor-elixir-phoenix-releases/)

### 12-Factor App
- [The Twelve-Factor App - Config](https://12factor.net/config)

### Configuration Libraries

**Vapor:**
- [GitHub: keathley/vapor](https://github.com/keathley/vapor)
- [Vapor Documentation](https://hexdocs.pm/vapor/Vapor.html)
- [Configuring Elixir at Runtime with Vapor - AppSignal](https://blog.appsignal.com/2020/04/28/configuring-your-elixir-application-at-runtime-with-vapor.html)
- [Runtime Configuration in Elixir Apps - Keathley.io](https://keathley.io/blog/vapor-and-configuration.html)

**Dotenvy:**
- [Dotenvy Documentation](https://hexdocs.pm/dotenvy/)
- [Configuration in Elixir with Dotenvy - Medium](https://fireproofsocks.medium.com/configuration-in-elixir-with-dotenvy-8b20f227fc0e)
- [Using Dotenvy in Elixir Releases - Medium](https://fireproofsocks.medium.com/using-dotenvy-in-elixir-releases-68e566c0bf9f)
- [Using Dotenvy with Phoenix](https://hexdocs.pm/dotenvy/phoenix.html)

**NimbleOptions:**
- [GitHub: dashbitco/nimble_options](https://github.com/dashbitco/nimble_options)
- [NimbleOptions Documentation](https://hexdocs.pm/nimble_options/NimbleOptions.html)
- [Validating Data in Elixir - AppSignal](https://blog.appsignal.com/2023/11/07/validating-data-in-elixir-using-ecto-and-nimbleoptions.html)
- [Improving Elixir Argument Validation - Elixir Merge](https://elixirmerge.com/p/improving-elixir-argument-validation-with-nimbleoptions)

### Feature Flags

**FunWithFlags:**
- [GitHub: tompave/fun_with_flags](https://github.com/tompave/fun_with_flags)
- [How to Add Feature Flags in Phoenix - DockYard](https://dockyard.com/blog/2023/02/28/how-to-add-feature-flags-in-a-phoenix-application-using-fun_with_flags)
- [Feature Flagging in Elixir - Britton Broderick](https://brittonbroderick.com/2022/11/29/feature-flagging-in-elixir-with-funwithflags/)
- [Feature Flags - ElixirCasts](https://elixircasts.io/feature-flags)

**General Feature Flags:**
- [Feature Toggles - Martin Fowler](https://martinfowler.com/articles/feature-toggles.html)
- [How to build the simplest feature flag system](https://www.chriis.dev/opinion/how-to-build-the-simplest-feature-flag-system-in-elixir-and-phoenix-apps)

**Canary Deployments:**
- [Canary Deployment with Feature Flags - Unleash](https://www.getunleash.io/blog/canary-deployment-what-is-it)
- [Understanding Canary Releases - Harness](https://www.harness.io/blog/canary-release-feature-flags)
- [GradualRollout - Feature flags and canary deployments](https://gradualrollout.com/)

### Testing
- [Testing Environment Variables in Phoenix - Sean Lawrence](https://www.sean-lawrence.com/testing-environment-variables-in-an-elixir-phoenix-application/)
- [Mocks in Elixir/Phoenix using Behaviors - Medium](https://brooklinmyers.medium.com/mocks-in-elixir-phoenix-using-behaviors-and-environment-variables-7e41dfd749ae)
- [Setting up Phoenix CI/CD on GitLab](https://experimentingwithcode.com/setting-up-a-phoenix-ci-cd-pipeline-on-gitlab-part-1/)
- [Improving Testing & CI in Phoenix - Phoenix Blog](https://www.phoenixframework.org/blog/improving-testing-and-continuous-integration-in-phoenix)

### Community Discussions
- [System.get_env vs. Application.get_env - Elixir Forum](https://elixirforum.com/t/system-get-env-vs-application-get-env/11246)
- [Why Phoenix isn't merging configs - Elixir Forum](https://elixirforum.com/t/why-phoenix-isnt-merging-config-exs-and-runtime-exs-configs/37601)
- [Runtime configuration library - Elixir Forum](https://elixirforum.com/t/runtime-configuration-library-with-casting-validation-etc-for-native-releases/29365)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-08
**Research Scope:** Phoenix 1.7+, Elixir 1.11+, Modern best practices as of 2024-2025
