defmodule GscAnalytics.Accounts do
  @moduledoc """
  Convenience helpers for working with configured Google Search Console accounts.

  The application ships with a static account registry defined in configuration.
  This module layers runtime overrides on top (stored in `gsc_account_settings`)
  so operators can adjust display names and, most importantly, persist the
  default Search Console property selected through the UI.
  """

  import Ecto.Query

  alias GscAnalytics.Auth.Scope
  alias GscAnalytics.Auth.User
  alias GscAnalytics.Accounts.AccountSetting
  alias GscAnalytics.Schemas.WorkspaceProperty
  alias GscAnalytics.Schemas.Workspace
  alias GscAnalytics.Workspaces
  alias GscAnalytics.DataSources.GSC.Core.Client, as: GSCClient
  alias GscAnalytics.Repo

  @type account_id :: pos_integer()

  @doc """
  Returns the list of account identifiers accessible to the given user.

  Multi-tenant membership is not implemented yet, so all enabled accounts
  are exposed by default.
  """
  @spec account_ids_for_user(term()) :: [account_id()]
  def account_ids_for_user(%User{id: user_id}) do
    Workspaces.list_workspaces(user_id, enabled_only: true)
    |> Enum.map(& &1.id)
  end

  def account_ids_for_user(nil), do: []

  @doc """
  Returns the default workspace ID for the user (first enabled workspace).
  """
  @spec default_account_id() :: account_id() | nil
  def default_account_id do
    # Without a scope, we can't determine the user, so return nil
    nil
  end

  @spec default_account_id(Scope.t() | nil) :: account_id() | nil
  def default_account_id(%Scope{user: %{id: user_id}}) do
    case Workspaces.get_default_workspace(user_id) do
      %Workspace{id: id} -> id
      nil -> nil
    end
  end

  def default_account_id(nil), do: nil

  @doc """
  Resolves the requested account identifier from assorted option structures.

  Accepts maps (string or atom keys), keyword lists, bare integers, or `nil`.
  Falls back to the configured default account when not provided.
  """
  @spec resolve_account_id(term()) :: account_id()
  def resolve_account_id(nil), do: default_account_id()

  def resolve_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: account_id

  def resolve_account_id(opts) when is_map(opts) do
    Map.get(opts, :account_id) ||
      Map.get(opts, "account_id") ||
      default_account_id()
  end

  def resolve_account_id(opts) when is_list(opts) do
    Keyword.get(opts, :account_id, default_account_id())
  end

  def resolve_account_id(_), do: default_account_id()

  @doc """
  Lists workspaces for the current user, transformed into account maps.
  """
  @spec list_gsc_accounts() :: [map()]
  def list_gsc_accounts do
    # Without scope, return empty list (can't determine user)
    []
  end

  @spec list_gsc_accounts(keyword()) :: [map()]
  def list_gsc_accounts(opts) when is_list(opts) do
    # Without scope, return empty list
    []
  end

  @spec list_gsc_accounts(Scope.t() | nil) :: [map()]
  def list_gsc_accounts(%Scope{user: %{id: user_id}} = _scope) do
    user_id
    |> Workspaces.list_workspaces(enabled_only: true)
    |> Enum.map(&workspace_to_account_map/1)
    |> enrich_accounts()
  end

  def list_gsc_accounts(nil) do
    []
  end

  @spec list_gsc_accounts(Scope.t() | nil, keyword()) :: [map()]
  def list_gsc_accounts(%Scope{user: %{id: user_id}} = _scope, opts) when is_list(opts) do
    # Extract enabled_only from opts, default to false
    enabled_only = Keyword.get(opts, :enabled_only, false)

    user_id
    |> Workspaces.list_workspaces(enabled_only: enabled_only)
    |> Enum.map(&workspace_to_account_map/1)
    |> enrich_accounts()
  end

  def list_gsc_accounts(nil, opts) when is_list(opts) do
    []
  end

  @doc """
  Fetch a single workspace by ID and convert to account map.
  """
  @spec fetch_gsc_account(account_id()) :: {:ok, map()} | {:error, term()}
  def fetch_gsc_account(account_id) do
    case Workspaces.get_workspace(account_id) do
      %Workspace{} = workspace ->
        account_map = workspace_to_account_map(workspace)
        {:ok, account_map}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Fetch a single workspace by ID, raising when unavailable.
  """
  @spec fetch_gsc_account!(account_id()) :: map()
  def fetch_gsc_account!(account_id) do
    case fetch_gsc_account(account_id) do
      {:ok, account} -> account
      {:error, :not_found} -> raise "Workspace #{account_id} not found"
    end
  end

  @doc """
  Builds account options suitable for dropdown selectors.
  """
  @spec gsc_account_options() :: [{String.t(), account_id()}]
  def gsc_account_options do
    list_gsc_accounts()
    |> Enum.map(fn %{id: id, display_name: display_name} -> {display_name, id} end)
  end

  @spec gsc_account_options(Scope.t() | nil) :: [{String.t(), account_id()}]
  def gsc_account_options(%Scope{} = scope) do
    list_gsc_accounts(scope)
    |> Enum.map(fn %{id: id, display_name: display_name} -> {display_name, id} end)
  end

  def gsc_account_options(nil), do: gsc_account_options()

  # Legacy gsc_default_property functions removed - use get_active_property_url instead

  # ---------------------------------------------------------------------------
  # Multi-property management
  # ---------------------------------------------------------------------------

  @doc """
  List all properties for a workspace, ordered by is_active desc, then display_name.
  """
  @spec list_properties(account_id()) :: [WorkspaceProperty.t()]
  def list_properties(account_id) do
    WorkspaceProperty
    |> where(workspace_id: ^account_id)
    |> order_by([p], desc: p.is_active, asc: p.display_name)
    |> Repo.all()
  end

  @doc """
  List active properties for a workspace ordered by most recently updated.
  """
  @spec list_active_properties(account_id()) :: [WorkspaceProperty.t()]
  def list_active_properties(account_id) do
    WorkspaceProperty
    |> where([p], p.workspace_id == ^account_id and p.is_active == true)
    |> order_by([p], desc: p.updated_at, desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Add a new property to a workspace.
  Properties are activated by default unless explicitly set to inactive.
  Returns {:ok, property} or {:error, changeset}.
  """
  @spec add_property(account_id(), map()) ::
          {:ok, WorkspaceProperty.t()} | {:error, Ecto.Changeset.t()}
  def add_property(account_id, attrs) do
    # Auto-activate properties by default for better UX
    attrs_with_defaults = Map.put_new(attrs, :is_active, true)

    %WorkspaceProperty{}
    |> WorkspaceProperty.changeset(Map.merge(attrs_with_defaults, %{workspace_id: account_id}))
    |> Repo.insert()
  end

  @doc """
  Mark a property as active for the workspace. Multiple properties may be active at once.
  Returns {:ok, property} or {:error, reason}.
  """
  @spec set_active_property(account_id(), String.t()) ::
          {:ok, WorkspaceProperty.t()} | {:error, term()}
  def set_active_property(account_id, property_id) do
    update_property_active(account_id, property_id, true)
  end

  @doc """
  Update the active flag for a workspace property.
  """
  @spec update_property_active(account_id(), String.t(), boolean()) ::
          {:ok, WorkspaceProperty.t()} | {:error, term()}
  def update_property_active(account_id, property_id, active?) when is_boolean(active?) do
    with {:ok, uuid} <- validate_uuid(property_id),
         %WorkspaceProperty{} = property <-
           Repo.get_by(WorkspaceProperty, id: uuid, workspace_id: account_id) do
      property
      |> WorkspaceProperty.changeset(%{is_active: active?})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Remove a property from a workspace.
  Returns {:ok, property} or {:error, reason}.
  """
  @spec remove_property(account_id(), String.t()) ::
          {:ok, WorkspaceProperty.t()} | {:error, term()}
  def remove_property(account_id, property_id) do
    with {:ok, uuid} <- validate_uuid(property_id) do
      property = Repo.get_by(WorkspaceProperty, id: uuid, workspace_id: account_id)

      case property do
        nil -> {:error, :not_found}
        property -> Repo.delete(property)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get the active property for a workspace.
  Returns property struct or nil.
  """
  @spec get_active_property(account_id()) :: WorkspaceProperty.t() | nil
  def get_active_property(account_id) do
    account_id
    |> list_active_properties()
    |> List.first()
  end

  @doc """
  Get the active property URL for a workspace.
  Returns error if no active property is set.
  """
  @spec get_active_property_url(account_id()) :: {:ok, String.t()} | {:error, term()}
  def get_active_property_url(account_id) do
    case get_active_property(account_id) do
      nil ->
        {:error, :no_active_property}

      property ->
        {:ok, property.property_url}
    end
  end

  @doc """
  Find a property by its property_url.
  Returns property struct or nil.
  """
  @spec get_property_by_url(account_id(), String.t()) :: WorkspaceProperty.t() | nil
  def get_property_by_url(account_id, property_url) do
    Repo.get_by(WorkspaceProperty, workspace_id: account_id, property_url: property_url)
  end

  @doc """
  Returns the list of Search Console properties available to the given account.
  Enriches the response with saved property information.

  Returns both:
  1. Properties currently available via GSC API (can sync)
  2. Saved properties without API access (historical data only)
  """
  @spec list_property_options(Scope.t() | nil, account_id(), [WorkspaceProperty.t()] | nil) ::
          {:ok, [map()]} | {:error, term()}
  def list_property_options(scope, account_id, preloaded_properties \\ nil) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(scope, account_id) do
      # Use preloaded properties if provided, otherwise query database
      saved_properties = preloaded_properties || list_properties(account_id)
      saved_urls = MapSet.new(saved_properties, & &1.property_url)

      # Get properties from GSC API
      case GSCClient.list_sites(account_id) do
        {:ok, sites} ->
          # Build a set of API-available property URLs
          api_urls = MapSet.new(sites, & &1.site_url)

          # Process API properties - mark which ones are saved
          api_properties =
            sites
            |> Enum.map(&build_property_option/1)
            |> Enum.map(fn opt ->
              opt
              |> Map.put(:is_saved, MapSet.member?(saved_urls, opt.value))
              |> Map.put(:has_api_access, true)
            end)

          # Find saved properties that DON'T have API access anymore
          # These are historical properties we want to preserve access to
          historical_properties =
            saved_properties
            |> Enum.reject(fn prop -> MapSet.member?(api_urls, prop.property_url) end)
            |> Enum.map(fn prop ->
              %{
                value: prop.property_url,
                label: prop.display_name || infer_property_label(prop.property_url),
                is_saved: true,
                is_active: prop.is_active,
                permission_level: "historical",
                has_api_access: false
              }
            end)

          # Combine both lists and sort
          all_properties =
            (api_properties ++ historical_properties)
            |> Enum.sort_by(&property_option_sort_key/1)

          {:ok, all_properties}

        {:error, :oauth_token_invalid} = error ->
          # OAuth token is invalid - needs re-authentication
          error

        {:error, {:oauth_refresh_failed, :oauth_token_invalid}} ->
          # OAuth token is invalid - needs re-authentication (from Authenticator wrapper)
          {:error, :oauth_token_invalid}

        {:error, _error} ->
          # If API fails, return saved properties with no API access flag
          saved =
            saved_properties
            |> Enum.map(fn prop ->
              %{
                value: prop.property_url,
                label: prop.display_name || infer_property_label(prop.property_url),
                is_saved: true,
                is_active: prop.is_active,
                permission_level: "unknown",
                has_api_access: false
              }
            end)
            |> Enum.sort_by(&property_option_sort_key/1)

          {:ok, saved}
      end
    end
  end

  # Legacy set_default_property removed - use add_property and set_active_property instead

  @doc """
  Update the display name shown for an account (optional quality-of-life tweak).
  """
  @spec set_display_name(Scope.t() | nil, account_id(), String.t()) ::
          {:ok, AccountSetting.t()} | {:error, term()}
  def set_display_name(scope, account_id, display_name) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(scope, account_id) do
      normalized =
        display_name
        |> to_string()
        |> String.trim()
        |> case do
          "" -> nil
          value -> value
        end

      upsert_account_setting(account_id, %{display_name: normalized})
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Convert a Workspace struct to an account map for backward compatibility
  defp workspace_to_account_map(%Workspace{} = workspace) do
    %{
      id: workspace.id,
      name: workspace.google_account_email,
      display_name: workspace.name || workspace.google_account_email,
      enabled?: workspace.enabled,
      oauth: %{
        google_email: workspace.google_account_email
      }
    }
  end

  defp enrich_accounts(accounts) do
    ids = Enum.map(accounts, & &1.id)

    settings_by_id =
      case ids do
        [] ->
          %{}

        _ ->
          AccountSetting
          |> where([s], s.account_id in ^ids)
          |> Repo.all()
          |> Map.new(&{&1.account_id, &1})
      end

    Enum.map(accounts, fn account ->
      setting = Map.get(settings_by_id, account.id)
      display_name = compute_display_name(account, setting)

      account
      |> Map.put(:display_name, display_name)
    end)
  end

  defp compute_display_name(account, setting) do
    cond do
      setting && setting.display_name && String.trim(setting.display_name) != "" ->
        String.trim(setting.display_name)

      account.name && String.trim(account.name) != "" ->
        String.trim(account.name)

      true ->
        "Workspace #{account.id}"
    end
  end

  defp upsert_account_setting(account_id, attrs) do
    case Repo.get(AccountSetting, account_id) do
      nil ->
        %AccountSetting{account_id: account_id}
        |> AccountSetting.changeset(Map.put(attrs, :account_id, account_id))
        |> Repo.insert()

      %AccountSetting{} = existing ->
        existing
        |> AccountSetting.changeset(attrs)
        |> Repo.update()
    end
  end

  defp build_property_option(%{site_url: site_url, permission_level: permission} = site) do
    %{
      value: site_url,
      label: infer_property_label(site_url),
      permission_level: permission || "unknown",
      raw: site
    }
  end

  defp property_option_sort_key(%{permission_level: permission, value: value, label: label}) do
    perm_rank =
      case String.downcase(to_string(permission || "")) do
        level when level in ["siteowner", "owner", "verified"] -> 0
        "full" -> 1
        "view" -> 2
        "restricted" -> 3
        _ -> 9
      end

    type_rank = if String.starts_with?(value, "sc-domain:"), do: 0, else: 1

    {perm_rank, type_rank, String.downcase(label || value || "")}
  end

  defp infer_property_label("sc-domain:" <> rest), do: "Domain: #{rest}"

  defp infer_property_label(site_url) when is_binary(site_url) do
    case URI.parse(site_url) do
      %URI{scheme: scheme, host: host, path: path} when is_binary(host) ->
        base = "#{scheme}://#{host}"

        cond do
          path in [nil, "", "/"] -> base
          true -> base <> path
        end

      _ ->
        site_url
    end
  end

  defp infer_property_label(_), do: nil

  defp normalize_account_id(account_id) when is_integer(account_id) and account_id > 0,
    do: {:ok, account_id}

  defp normalize_account_id(account_id) when is_binary(account_id) do
    case Integer.parse(account_id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, :invalid_account_id}
    end
  end

  defp normalize_account_id(_), do: {:error, :invalid_account_id}

  defp validate_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, valid_uuid} -> {:ok, valid_uuid}
      :error -> {:error, :invalid_uuid}
    end
  end

  defp validate_uuid(_), do: {:error, :invalid_uuid}
end
