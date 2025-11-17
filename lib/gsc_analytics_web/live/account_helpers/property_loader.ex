defmodule GscAnalyticsWeb.Live.AccountHelpers.PropertyLoader do
  @moduledoc """
  Handles fetching and caching of Google Search Console properties.

  This module is responsible for:
  - Batch loading properties for multiple accounts
  - Verifying API access via OAuth tokens
  - Filtering properties based on current API accessibility
  - Managing OAuth token lifecycle

  ## Design Philosophy

  - **Batch operations**: Load all properties in a single query to avoid N+1
  - **Graceful degradation**: Fall back to saved properties if API calls fail
  - **OAuth-aware**: Only show properties accessible via current OAuth token
  - **Cache-friendly**: Support both database queries and preloaded caches
  """

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.WorkspaceProperty
  alias GscAnalytics.DataSources.GSC.Support.Authenticator
  alias GscAnalytics.DataSources.GSC.Core.Client, as: GSCClient

  @doc """
  Load properties for all accounts with API access filtering.

  Returns a tuple of `{properties_by_account, oauth_tokens}` where:
  - `properties_by_account` - Map of account_id => [properties]
  - `oauth_tokens` - Map of account_id => oauth_token

  ## Behavior

  For each account:
  1. Batch load saved properties from database
  2. Check if OAuth token exists
  3. If token exists, verify API access and filter properties
  4. If token missing or API call fails, fall back to saved properties

  This ensures historical data remains accessible even after OAuth revocation.

  ## Examples

      iex> accounts = [%{id: 1}, %{id: 2}]
      iex> scope = %Auth.Scope{user: user, account_ids: [1, 2]}
      iex> {properties_by_account, tokens} = PropertyLoader.load_properties_by_account(accounts, scope, nil)
      iex> Map.keys(properties_by_account)
      [1, 2]
  """
  @spec load_properties_by_account(list(map()), map(), map() | nil) ::
          {map(), map()}
  def load_properties_by_account(accounts, scope, oauth_tokens_map) do
    # Batch load ALL properties for ALL accounts in a single query
    # This prevents N+1 queries (was calling list_properties once per account)
    account_ids = Enum.map(accounts, & &1.id)
    all_properties = batch_load_all_properties(account_ids)

    # Reuse preloaded OAuth tokens when available to avoid duplicate queries
    oauth_tokens = ensure_oauth_tokens(oauth_tokens_map, scope, accounts)

    properties_by_account =
      Enum.reduce(accounts, %{}, fn account, acc ->
        # Get pre-loaded properties for this account
        saved_properties = Map.get(all_properties, account.id, [])

        # Only show properties that are accessible via current OAuth token
        # This prevents showing stale properties from previous Google accounts
        properties =
          case Map.get(oauth_tokens, account.id) do
            nil ->
              # No OAuth token available - fall back to saved properties so historical
              # data remains accessible even if access has been revoked.
              saved_properties

            _token ->
              # OAuth token exists - get API-accessible properties
              # Note: We pass saved_properties to avoid re-querying the database
              case get_api_accessible_properties(scope, account.id, saved_properties) do
                {:ok, api_property_urls} ->
                  # Use pre-loaded properties, filtered by API access
                  saved_properties
                  |> Enum.filter(fn prop ->
                    MapSet.member?(api_property_urls, prop.property_url)
                  end)

                {:error, _} ->
                  # If OAuth API call fails, fall back to saved properties
                  saved_properties
              end
          end

        Map.put(acc, account.id, properties)
      end)

    {properties_by_account, oauth_tokens}
  end

  @doc """
  Load properties from preloaded cache instead of querying database.

  Same as `load_properties_by_account/3` but accepts a preloaded property map.
  Useful when properties have already been batch-loaded elsewhere.

  ## Examples

      iex> preloaded = %{1 => [prop1, prop2], 2 => [prop3]}
      iex> {properties, tokens} = PropertyLoader.load_properties_from_cache(accounts, scope, preloaded, nil)
  """
  @spec load_properties_from_cache(list(map()), map(), map(), map() | nil) ::
          {map(), map()}
  def load_properties_from_cache(accounts, scope, all_properties, oauth_tokens_map) do
    oauth_tokens = ensure_oauth_tokens(oauth_tokens_map, scope, accounts)

    properties_by_account =
      Enum.reduce(accounts, %{}, fn account, acc ->
        # Get pre-loaded properties for this account
        saved_properties = Map.get(all_properties, account.id, [])

        # Only show properties that are accessible via current OAuth token
        properties =
          case Map.get(oauth_tokens, account.id) do
            nil ->
              saved_properties

            _token ->
              case get_api_accessible_properties(scope, account.id, saved_properties) do
                {:ok, api_property_urls} ->
                  saved_properties
                  |> Enum.filter(fn prop ->
                    MapSet.member?(api_property_urls, prop.property_url)
                  end)

                {:error, _} ->
                  saved_properties
              end
          end

        Map.put(acc, account.id, properties)
      end)

    {properties_by_account, oauth_tokens}
  end

  @doc """
  Batch load all properties for multiple accounts in a single query.

  Returns a map of `account_id => [properties]`.

  ## Examples

      iex> PropertyLoader.batch_load_all_properties([1, 2, 3])
      %{1 => [prop1, prop2], 2 => [prop3], 3 => []}
  """
  @spec batch_load_all_properties(list(integer())) :: map()
  def batch_load_all_properties(account_ids) when is_list(account_ids) do
    from(p in WorkspaceProperty,
      where: p.workspace_id in ^account_ids,
      where: p.is_active == true,
      order_by: [desc: p.is_active, asc: p.display_name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.workspace_id)
  end

  @doc """
  Get API-accessible property URLs for an account without re-querying database.

  Checks which saved properties are currently accessible via GSC API.
  Returns `{:ok, mapset_of_urls}` or `{:error, reason}`.

  ## Behavior

  - Authorizes account via scope
  - Fetches sites from GSC API
  - Filters to only include saved properties (ignores new properties not in DB)
  - Returns MapSet for efficient membership testing

  ## Examples

      iex> saved_props = [%{property_url: "sc-domain:example.com"}]
      iex> {:ok, urls} = PropertyLoader.get_api_accessible_properties(scope, 1, saved_props)
      iex> MapSet.member?(urls, "sc-domain:example.com")
      true
  """
  @spec get_api_accessible_properties(map(), integer(), list(map())) ::
          {:ok, MapSet.t(String.t())} | {:error, term()}
  def get_api_accessible_properties(scope, account_id, saved_properties) do
    with :ok <- GscAnalytics.Auth.Scope.authorize_account(scope, account_id) do
      saved_urls = MapSet.new(saved_properties, & &1.property_url)

      # Get properties from GSC API
      case GSCClient.list_sites(account_id) do
        {:ok, sites} ->
          # Build a set of API-available property URLs that are also saved
          api_property_urls =
            sites
            |> Enum.map(& &1.site_url)
            |> Enum.filter(&MapSet.member?(saved_urls, &1))
            |> MapSet.new()

          {:ok, api_property_urls}

        {:error, :authenticator_not_started} ->
          # Test mode: Assume all saved properties are API-accessible
          {:ok, saved_urls}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helpers - OAuth Token Management
  # ---------------------------------------------------------------------------

  defp ensure_oauth_tokens(nil, scope, accounts) do
    account_ids = Enum.map(accounts, & &1.id)
    oauth_tokens = fetch_oauth_tokens(scope, account_ids)
    # Cache tokens in Authenticator to avoid individual DB lookups
    Authenticator.cache_tokens(oauth_tokens)
    oauth_tokens
  end

  defp ensure_oauth_tokens(tokens, _scope, _accounts) when is_map(tokens), do: tokens

  defp fetch_oauth_tokens(_scope, []), do: %{}

  defp fetch_oauth_tokens(scope, account_ids) do
    oauth_tokens = GscAnalytics.Auth.batch_get_oauth_tokens(scope, account_ids)
    # Cache tokens in Authenticator to avoid individual DB lookups
    Authenticator.cache_tokens(oauth_tokens)
    oauth_tokens
  end
end
