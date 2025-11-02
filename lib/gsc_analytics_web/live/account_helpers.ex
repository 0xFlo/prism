defmodule GscAnalyticsWeb.Live.AccountHelpers do
  @moduledoc """
  Shared helpers for LiveViews that need to expose Google Search Console account
  and property selections. Provides a consistent way to determine the active
  Google account (credential) and the active property beneath it, while keeping
  layout assigns in sync.
  """

  use Phoenix.Component

  alias GscAnalytics.Accounts

  @type socket :: Phoenix.LiveView.Socket.t()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Initialise account assigns on the socket and return the selected account.

  We respect `account_id` when present; otherwise, we fall back to a default
  account. Properties for each Google account are cached so subsequent lookups
  are quick.

  Returns {socket, nil} if no workspaces exist (allows Settings page to load).
  """
  @spec init_account_assigns(socket(), map()) :: {socket(), map() | nil}
  def init_account_assigns(socket, params \\ %{}) do
    current_scope = Map.get(socket.assigns, :current_scope)
    accounts = Accounts.list_gsc_accounts(current_scope)

    # Handle empty workspace state gracefully
    if Enum.empty?(accounts) do
      socket =
        socket
        |> assign(:accounts_by_id, %{})
        |> assign(:account_options, [])
        |> assign(:properties_by_account, %{})
        |> assign(:current_account, nil)
        |> assign(:current_account_id, nil)

      {socket, nil}
    else
      # Enrich accounts with OAuth information via batch loading
      account_ids = Enum.map(accounts, & &1.id)
      oauth_tokens = GscAnalytics.Auth.batch_get_oauth_tokens(current_scope, account_ids)

      accounts =
        Enum.map(accounts, fn account ->
          oauth =
            case Map.get(oauth_tokens, account.id) do
              nil -> nil
              token -> %{google_email: token.google_email}
            end

          Map.put(account, :oauth, oauth)
        end)

      accounts_by_id = Map.new(accounts, fn account -> {account.id, account} end)

      socket =
        socket
        |> assign(:accounts_by_id, accounts_by_id)
        |> assign(:account_options, Accounts.gsc_account_options(current_scope))
        |> reload_property_state()

      requested_account_id = params |> Map.get("account_id") |> parse_account_param()
      requested_property_id = params |> Map.get("property_id") |> parse_property_param()

      account_id =
        resolve_account_id(socket, requested_account_id, requested_property_id, current_scope)

      socket = set_account(socket, account_id, requested_property_id)
      {socket, socket.assigns.current_account}
    end
  end

  @doc """
  Initialise both account and property assigns. Returns `{socket, account, property}`.

  Returns {socket, nil, nil} if no workspaces exist.
  """
  @spec init_account_and_property_assigns(socket(), map()) :: {socket(), map() | nil, map() | nil}
  def init_account_and_property_assigns(socket, params \\ %{}) do
    {socket, account} = init_account_assigns(socket, params)

    # If no account exists (empty workspaces), skip property assignment
    if is_nil(account) do
      socket =
        socket
        |> assign(:current_property, nil)
        |> assign(:current_property_id, nil)
        |> assign(:property_options, [])
        |> assign(:property_options_all, [])
        |> assign(:property_lookup, %{})

      {socket, nil, nil}
    else
      socket = assign_current_property(socket, params)
      {socket, socket.assigns.current_account, socket.assigns.current_property}
    end
  end

  @doc """
  Update the current account selection based on params.

  ## Options
  - `:skip_reload` - Skip reloading properties if they're already cached (default: false)
  """
  @spec assign_current_account(socket(), map(), keyword()) :: socket()
  def assign_current_account(socket, params \\ %{}, opts \\ []) do
    requested_id = params |> Map.get("account_id") |> parse_account_param()
    current_scope = Map.get(socket.assigns, :current_scope)

    socket =
      if Keyword.get(opts, :skip_reload, false) do
        socket
      else
        reload_property_state(socket)
      end

    account_id = resolve_account_id(socket, requested_id, nil, current_scope)
    set_account(socket, account_id)
  end

  @doc """
  Update the current property selection. If the property belongs to a different
  account, switch to that account automatically before selecting the property.

  ## Options
  - `:skip_reload` - Skip reloading properties if they're already cached (default: false)
  """
  @spec assign_current_property(socket(), map(), keyword()) :: socket()
  def assign_current_property(socket, params \\ %{}, opts \\ []) do
    property_id = params |> Map.get("property_id") |> parse_property_param()

    socket =
      if Keyword.get(opts, :skip_reload, false) do
        socket
      else
        reload_property_state(socket)
      end

    account_id =
      case map_property_to_account(socket, property_id) do
        {:ok, id} -> id
        :error -> socket.assigns.current_account_id
      end

    socket
    |> set_account(account_id, property_id)
  end

  @doc """
  Refresh cached property lists and lookup tables. Useful after mutating property data.
  """
  @spec reload_properties(socket()) :: socket()
  def reload_properties(socket) do
    socket =
      socket
      |> reload_property_state()

    account_id = socket.assigns[:current_account_id]
    property_id = socket.assigns[:current_property_id]

    if account_id do
      set_account(socket, account_id, property_id)
    else
      socket
    end
  end

  @doc """
  Reload properties from preloaded cache. Avoids re-querying the database.
  Useful when properties have already been batch-loaded elsewhere.
  """
  @spec reload_properties_from_cache(socket(), map()) :: socket()
  def reload_properties_from_cache(socket, preloaded_properties)
      when is_map(preloaded_properties) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})
    accounts = Map.values(accounts_by_id)
    scope = Map.get(socket.assigns, :current_scope)

    # Use preloaded properties instead of querying
    properties_by_account =
      load_properties_by_account_from_cache(accounts, scope, preloaded_properties)

    property_lookup = build_property_lookup(properties_by_account)
    property_options = build_property_options(properties_by_account, accounts_by_id)

    socket =
      socket
      |> assign(:properties_by_account, properties_by_account)
      |> assign(:property_lookup, property_lookup)
      |> assign(:property_options_all, property_options)

    account_id = socket.assigns[:current_account_id]
    property_id = socket.assigns[:current_property_id]

    if account_id do
      set_account(socket, account_id, property_id)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Parsing helpers
  # ---------------------------------------------------------------------------

  @spec parse_account_param(term()) :: integer() | nil
  def parse_account_param(nil), do: nil
  def parse_account_param(value) when is_integer(value) and value > 0, do: value

  def parse_account_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  def parse_account_param(_), do: nil

  @spec parse_property_param(term()) :: String.t() | nil
  def parse_property_param(nil), do: nil
  def parse_property_param(value) when is_binary(value) and value != "", do: value
  def parse_property_param(_), do: nil

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp resolve_account_id(socket, requested_account_id, requested_property_id, current_scope) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})

    cond do
      requested_property_id &&
          match?({:ok, _id}, map_property_to_account(socket, requested_property_id)) ->
        {:ok, account_id} = map_property_to_account(socket, requested_property_id)
        account_id

      requested_account_id && Map.has_key?(accounts_by_id, requested_account_id) ->
        requested_account_id

      socket.assigns[:current_account_id] &&
          Map.has_key?(accounts_by_id, socket.assigns.current_account_id) ->
        socket.assigns.current_account_id

      true ->
        case resolve_initial_account(current_scope, accounts_by_id, requested_account_id) do
          nil -> nil
          account -> account.id
        end
    end
  end

  defp resolve_initial_account(current_scope, accounts_by_id, requested_id) do
    accounts = Map.values(accounts_by_id)
    default_account_id = Accounts.default_account_id(current_scope)

    cond do
      requested_id && Map.has_key?(accounts_by_id, requested_id) ->
        Map.fetch!(accounts_by_id, requested_id)

      default_account_id && Map.has_key?(accounts_by_id, default_account_id) ->
        Map.fetch!(accounts_by_id, default_account_id)

      true ->
        accounts
        |> Enum.sort_by(& &1.id)
        |> List.first()
    end
  end

  defp set_account(socket, account_id, requested_property_id \\ nil)
  defp set_account(socket, nil, _requested_property_id), do: socket

  defp set_account(socket, account_id, requested_property_id) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})
    properties_by_account = Map.get(socket.assigns, :properties_by_account, %{})

    account =
      Map.get(accounts_by_id, account_id) ||
        raise ArgumentError, "Unknown GSC account id #{inspect(account_id)}"

    properties = Map.get(properties_by_account, account_id, [])

    property_options =
      socket.assigns
      |> Map.get(:property_options_all)
      |> case do
        nil -> build_property_options(properties_by_account, accounts_by_id)
        options -> options
      end

    current_property = resolve_current_property(properties, requested_property_id)

    socket
    |> assign(:current_account, account)
    |> assign(:current_account_id, account.id)
    |> assign(:properties, properties)
    |> assign(:property_options, property_options)
    |> assign(:current_property, current_property)
    |> assign(:current_property_id, current_property && current_property.id)
  end

  defp resolve_current_property(properties, requested_id) do
    cond do
      requested_id ->
        Enum.find(properties, &(&1.id == requested_id)) ||
          Enum.find(properties, & &1.is_active) ||
          List.first(properties)

      true ->
        Enum.find(properties, & &1.is_active) || List.first(properties)
    end
  end

  defp load_properties_by_account(accounts, scope) do
    # Batch load ALL properties for ALL accounts in a single query
    # This prevents N+1 queries (was calling list_properties once per account)
    account_ids = Enum.map(accounts, & &1.id)
    all_properties = batch_load_all_properties(account_ids)

    # Batch load OAuth tokens to avoid N+1 OAuth token queries
    oauth_tokens = GscAnalytics.Auth.batch_get_oauth_tokens(scope, account_ids)

    Enum.reduce(accounts, %{}, fn account, acc ->
      # Get pre-loaded properties for this account
      saved_properties = Map.get(all_properties, account.id, [])

      # Only show properties that are accessible via current OAuth token
      # This prevents showing stale properties from previous Google accounts
      properties =
        case Map.get(oauth_tokens, account.id) do
          nil ->
            # No OAuth token - don't show any properties in navigation
            []

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
                # If OAuth API call fails, don't show any properties in navigation
                []
            end
        end

      Map.put(acc, account.id, properties)
    end)
  end

  # Same as load_properties_by_account but uses preloaded properties instead of querying
  defp load_properties_by_account_from_cache(accounts, scope, all_properties) do
    # Batch load OAuth tokens to avoid N+1 OAuth token queries
    account_ids = Enum.map(accounts, & &1.id)
    oauth_tokens = GscAnalytics.Auth.batch_get_oauth_tokens(scope, account_ids)

    Enum.reduce(accounts, %{}, fn account, acc ->
      # Get pre-loaded properties for this account
      saved_properties = Map.get(all_properties, account.id, [])

      # Only show properties that are accessible via current OAuth token
      properties =
        case Map.get(oauth_tokens, account.id) do
          nil ->
            []

          _token ->
            case get_api_accessible_properties(scope, account.id, saved_properties) do
              {:ok, api_property_urls} ->
                saved_properties
                |> Enum.filter(fn prop ->
                  MapSet.member?(api_property_urls, prop.property_url)
                end)

              {:error, _} ->
                []
            end
        end

      Map.put(acc, account.id, properties)
    end)
  end

  # Helper to get API-accessible property URLs without re-querying the database
  defp get_api_accessible_properties(scope, account_id, saved_properties) do
    alias GscAnalytics.DataSources.GSC.Core.Client, as: GSCClient

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

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp batch_load_all_properties(account_ids) when is_list(account_ids) do
    import Ecto.Query
    alias GscAnalytics.Schemas.WorkspaceProperty
    alias GscAnalytics.Repo

    from(p in WorkspaceProperty,
      where: p.workspace_id in ^account_ids,
      order_by: [desc: p.is_active, asc: p.display_name]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.workspace_id)
  end

  defp build_property_lookup(properties_by_account) do
    Enum.reduce(properties_by_account, %{}, fn {account_id, properties}, acc ->
      Enum.reduce(properties, acc, fn property, lookup ->
        Map.put(lookup, property.id, %{account_id: account_id, property: property})
      end)
    end)
  end

  defp build_property_options(properties_by_account, accounts_by_id) do
    properties_by_account
    |> Enum.sort_by(fn {account_id, _props} ->
      label = account_label(Map.get(accounts_by_id, account_id), account_id)
      {String.downcase(label), account_id}
    end)
    |> Enum.flat_map(fn {account_id, properties} ->
      label = account_label(Map.get(accounts_by_id, account_id), account_id)

      Enum.map(properties, fn property ->
        property_label = property_label(property)
        {"#{label} - #{property_label}", property.id}
      end)
    end)
  end

  defp account_label(nil, account_id), do: "Workspace #{account_id}"

  defp account_label(account, account_id) do
    cond do
      # Use OAuth email as first priority
      Map.get(account, :oauth) && account.oauth.google_email ->
        account.oauth.google_email

      # Fall back to display_name if set
      Map.get(account, :display_name) && String.trim(account.display_name) != "" ->
        String.trim(account.display_name)

      # Then try the configured name
      Map.get(account, :name) && String.trim(account.name) != "" ->
        String.trim(account.name)

      true ->
        "Workspace #{account_id}"
    end
  end

  defp property_label(property) do
    # Always use the actual property URL for consistency
    # This ensures all properties display uniformly (e.g., "sc-domain:example.com")
    property_url_label(property)
  end

  defp property_url_label(%{property_url: property_url}) when is_binary(property_url) do
    String.trim(property_url)
  end

  defp property_url_label(_property), do: "Property"

  defp reload_property_state(socket) do
    accounts_by_id = Map.get(socket.assigns, :accounts_by_id, %{})
    accounts = Map.values(accounts_by_id)
    scope = Map.get(socket.assigns, :current_scope)

    # Check if properties were already loaded in this request lifecycle
    # This prevents N+1 queries when reload_property_state is called multiple times
    # during mount → handle_params → assign_current_account → assign_current_property
    properties_by_account =
      case Map.get(socket.assigns, :_properties_cache) do
        nil ->
          # First load - query database and cache the result
          load_properties_by_account(accounts, scope)

        cached ->
          # Reuse cached properties from earlier in this request
          cached
      end

    property_lookup = build_property_lookup(properties_by_account)
    property_options = build_property_options(properties_by_account, accounts_by_id)

    socket
    |> assign(:properties_by_account, properties_by_account)
    |> assign(:property_lookup, property_lookup)
    |> assign(:property_options_all, property_options)
    |> assign(:_properties_cache, properties_by_account)
  end

  defp map_property_to_account(_socket, nil), do: :error

  defp map_property_to_account(socket, property_id) do
    socket.assigns
    |> Map.get(:property_lookup, %{})
    |> Map.get(property_id)
    |> case do
      %{account_id: account_id} -> {:ok, account_id}
      _ -> :error
    end
  end
end
