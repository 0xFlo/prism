defmodule GscAnalyticsWeb.Live.AccountHelpers.CacheManager do
  @moduledoc """
  Property cache management for LiveView socket assigns.

  This module handles caching of property data within the LiveView request lifecycle
  to prevent N+1 queries when the same data is accessed multiple times during:
  - mount → handle_params → assign_current_account → assign_current_property

  ## Design Philosophy

  - **Request-scoped**: Cache lives only within a single socket lifecycle
  - **Transparent**: Automatically reuses cached data when available
  - **Opt-in refresh**: Explicit reload when data changes
  - **Memory efficient**: Uses socket assigns (cleaned up on disconnect)

  ## Cache Strategy

  The cache uses a special `_properties_cache` assign to store properties_by_account.
  This prevents querying the database multiple times in a single request when:

  1. `init_account_assigns/2` is called
  2. `handle_params/3` runs and calls `assign_current_account/3`
  3. Property dropdown is rendered (needs property_options)
  4. Current property is resolved

  All these operations can reuse the same cached data.
  """

  alias GscAnalyticsWeb.Live.AccountHelpers.{PropertyLoader, UIFormatters}

  @doc """
  Reload property state from database with intelligent caching.

  Checks for cached properties in socket assigns. If found, reuses the cache.
  Otherwise, performs a fresh database query and caches the result.

  ## Parameters

  - `socket` - Phoenix LiveView socket
  - Must have assigns: `:accounts_by_id`, `:current_scope`, `:oauth_tokens_by_account`

  ## Returns

  Updated socket with assigns:
  - `:properties_by_account` - Map of account_id => [properties]
  - `:property_lookup` - Map of property_id => %{account_id, property}
  - `:property_options_all` - Formatted dropdown options
  - `:_properties_cache` - Cached properties_by_account (internal)
  - `:oauth_tokens_by_account` - OAuth tokens (refreshed if needed)

  ## Examples

      iex> socket = CacheManager.reload_property_state(socket)
      iex> socket.assigns[:properties_by_account]
      %{1 => [%WorkspaceProperty{}], 2 => [...]}
  """
  @spec reload_property_state(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload_property_state(socket) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})
    accounts = Map.values(accounts_by_id)
    scope = Map.get(socket.assigns, :current_scope)
    existing_tokens = Map.get(socket.assigns, :oauth_tokens_by_account)

    # Check if properties were already loaded in this request lifecycle
    # This prevents N+1 queries when reload_property_state is called multiple times
    # during mount → handle_params → assign_current_account → assign_current_property
    {properties_by_account, oauth_tokens} =
      case Map.get(socket.assigns, :_properties_cache) do
        nil ->
          # First load - query database and cache the result
          PropertyLoader.load_properties_by_account(accounts, scope, existing_tokens)

        cached ->
          # Reuse cached properties from earlier in this request
          {cached, ensure_oauth_tokens(existing_tokens, scope, accounts)}
      end

    property_lookup = UIFormatters.build_property_lookup(properties_by_account)
    property_options = UIFormatters.build_property_options(properties_by_account, accounts_by_id)

    socket
    |> Phoenix.Component.assign(:properties_by_account, properties_by_account)
    |> Phoenix.Component.assign(:property_lookup, property_lookup)
    |> Phoenix.Component.assign(:property_options_all, property_options)
    |> Phoenix.Component.assign(:_properties_cache, properties_by_account)
    |> Phoenix.Component.assign(:oauth_tokens_by_account, oauth_tokens)
  end

  @doc """
  Reload properties from preloaded cache.

  Like `reload_property_state/1` but uses preloaded properties instead of
  querying the database. Useful when properties have been batch-loaded elsewhere.

  ## Parameters

  - `socket` - Phoenix LiveView socket
  - `preloaded_properties` - Map of account_id => [properties]

  ## Examples

      iex> preloaded = %{1 => [prop1, prop2], 2 => [prop3]}
      iex> socket = CacheManager.reload_from_preloaded(socket, preloaded)
  """
  @spec reload_from_preloaded(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def reload_from_preloaded(socket, preloaded_properties) when is_map(preloaded_properties) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})
    accounts = Map.values(accounts_by_id)
    scope = Map.get(socket.assigns, :current_scope)
    existing_tokens = Map.get(socket.assigns, :oauth_tokens_by_account)

    # Use preloaded properties instead of querying
    {properties_by_account, oauth_tokens} =
      PropertyLoader.load_properties_from_cache(
        accounts,
        scope,
        preloaded_properties,
        existing_tokens
      )

    property_lookup = UIFormatters.build_property_lookup(properties_by_account)
    property_options = UIFormatters.build_property_options(properties_by_account, accounts_by_id)

    socket
    |> Phoenix.Component.assign(:properties_by_account, properties_by_account)
    |> Phoenix.Component.assign(:property_lookup, property_lookup)
    |> Phoenix.Component.assign(:property_options_all, property_options)
    |> Phoenix.Component.assign(:oauth_tokens_by_account, oauth_tokens)
  end

  @doc """
  Invalidate the property cache.

  Forces next call to `reload_property_state/1` to query the database.
  Use after adding/removing properties or changing account configuration.

  ## Examples

      iex> socket = CacheManager.invalidate_cache(socket)
      iex> socket.assigns[:_properties_cache]
      nil
  """
  @spec invalidate_cache(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def invalidate_cache(socket) do
    Phoenix.Component.assign(socket, :_properties_cache, nil)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers - OAuth Token Management
  # ---------------------------------------------------------------------------

  defp ensure_oauth_tokens(nil, scope, accounts) do
    account_ids = Enum.map(accounts, & &1.id)
    fetch_oauth_tokens(scope, account_ids)
  end

  defp ensure_oauth_tokens(tokens, _scope, _accounts) when is_map(tokens), do: tokens

  defp fetch_oauth_tokens(_scope, []), do: %{}

  defp fetch_oauth_tokens(scope, account_ids) do
    oauth_tokens = GscAnalytics.Auth.batch_get_oauth_tokens(scope, account_ids)
    # Cache tokens in Authenticator to avoid individual DB lookups
    GscAnalytics.DataSources.GSC.Support.Authenticator.cache_tokens(oauth_tokens)
    oauth_tokens
  end
end
