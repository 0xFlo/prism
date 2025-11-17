defmodule GscAnalyticsWeb.Live.AccountHelpers do
  @moduledoc """
  Shared helpers for LiveViews that need to expose Google Search Console account
  and property selections. Provides a consistent way to determine the active
  Google account (credential) and the active property beneath it, while keeping
  layout assigns in sync.

  ## Architecture

  This module is the main interface that delegates to specialized sub-modules:

  - `AccountHelpers.PropertyLoader` - Fetching and caching properties from database/API
  - `AccountHelpers.UIFormatters` - Display label formatting for dropdowns
  - `AccountHelpers.CacheManager` - Property cache lifecycle management

  ## Migration Notes

  This module maintains backward compatibility. All public functions that existed
  before the refactoring continue to work exactly as before, but now delegate to
  the appropriate sub-modules.
  """

  use Phoenix.Component

  alias GscAnalytics.Accounts
  alias GscAnalytics.DataSources.GSC.Support.Authenticator
  alias GscAnalyticsWeb.Live.AccountHelpers.{PropertyLoader, UIFormatters, CacheManager}

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

      # Pre-populate Authenticator cache to avoid individual DB lookups later
      Authenticator.cache_tokens(oauth_tokens)

      accounts =
        Enum.map(accounts, fn account ->
          oauth =
            case Map.get(oauth_tokens, account.id) do
              nil -> nil
              token -> %{google_email: token.google_email}
            end

          Map.put(account, :oauth, oauth)
        end)

      account_options =
        Enum.map(accounts, fn %{id: id, display_name: display_name} ->
          {display_name, id}
        end)

      accounts_by_id = Map.new(accounts, fn account -> {account.id, account} end)

      socket =
        socket
        |> assign(:accounts_by_id, accounts_by_id)
        |> assign(:account_options, account_options)
        |> assign(:oauth_tokens_by_account, oauth_tokens)
        |> CacheManager.reload_property_state()

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
        CacheManager.reload_property_state(socket)
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
        CacheManager.reload_property_state(socket)
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
      |> CacheManager.reload_property_state()

    account_id = socket.assigns[:current_account_id]
    property_id = socket.assigns[:current_property_id]

    if account_id do
      set_account(socket, account_id, property_id)
    else
      socket
    end
  end

  @doc """
  Extract a clean display label from a property URL.

  ## Examples

      iex> display_property_label("sc-domain:example.com")
      "example.com"

      iex> display_property_label("https://example.com/")
      "example.com"
  """
  @spec display_property_label(String.t() | nil) :: String.t() | nil
  def display_property_label(nil), do: nil

  def display_property_label(property_url) when is_binary(property_url) do
    UIFormatters.extract_domain(property_url)
  end

  @doc """
  Reload properties from preloaded cache. Avoids re-querying the database.
  Useful when properties have already been batch-loaded elsewhere.
  """
  @spec reload_properties_from_cache(socket(), map()) :: socket()
  def reload_properties_from_cache(socket, preloaded_properties)
      when is_map(preloaded_properties) do
    socket = CacheManager.reload_from_preloaded(socket, preloaded_properties)

    account_id = socket.assigns[:current_account_id]
    property_id = socket.assigns[:current_property_id]

    if account_id do
      set_account(socket, account_id, property_id)
    else
      socket
    end
  end

  # ---------------------------------------------------------------------------
  # Parsing helpers (backward compatibility - delegate to QueryParams in future)
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
        nil -> UIFormatters.build_property_options(properties_by_account, accounts_by_id)
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
