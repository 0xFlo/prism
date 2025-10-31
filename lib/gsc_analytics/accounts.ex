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
  alias GscAnalytics.Accounts.AccountSetting
  alias GscAnalytics.DataSources.GSC.Accounts, as: GSCAccounts
  alias GscAnalytics.DataSources.GSC.Core.Client, as: GSCClient
  alias GscAnalytics.DataSources.GSC.Core.Config, as: GSCConfig
  alias GscAnalytics.Repo

  @type account_id :: GSCAccounts.account_id()

  @doc """
  Returns the list of account identifiers accessible to the given user.

  Multi-tenant membership is not implemented yet, so all enabled accounts
  are exposed by default.
  """
  @spec account_ids_for_user(term()) :: [account_id()]
  def account_ids_for_user(_user) do
    list_gsc_accounts()
    |> Enum.map(& &1.id)
  end

  @doc """
  Returns the configured default GSC account identifier.
  """
  @spec default_account_id() :: account_id()
  def default_account_id do
    GSCConfig.default_account_id()
  end

  @spec default_account_id(Scope.t() | nil) :: account_id()
  def default_account_id(%Scope{}), do: default_account_id()
  def default_account_id(nil), do: default_account_id()

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
  Proxy to the configured GSC account registry, enriched with runtime overrides.
  """
  @spec list_gsc_accounts() :: [map()]
  def list_gsc_accounts do
    GSCAccounts.list_accounts([])
    |> enrich_accounts()
  end

  @spec list_gsc_accounts(keyword()) :: [map()]
  def list_gsc_accounts(opts) when is_list(opts) do
    GSCAccounts.list_accounts(opts)
    |> enrich_accounts()
  end

  @spec list_gsc_accounts(Scope.t() | nil) :: [map()]
  def list_gsc_accounts(%Scope{} = scope) do
    GSCAccounts.list_accounts([])
    |> filter_accounts_by_scope(scope)
    |> enrich_accounts()
  end

  def list_gsc_accounts(nil) do
    list_gsc_accounts()
  end

  @spec list_gsc_accounts(Scope.t() | nil, keyword()) :: [map()]
  def list_gsc_accounts(%Scope{} = scope, opts) when is_list(opts) do
    GSCAccounts.list_accounts(opts)
    |> filter_accounts_by_scope(scope)
    |> enrich_accounts()
  end

  def list_gsc_accounts(nil, opts) when is_list(opts) do
    GSCAccounts.list_accounts(opts)
    |> enrich_accounts()
  end

  @doc """
  Fetch a single GSC account definition.
  """
  @spec fetch_gsc_account(account_id()) ::
          {:ok, GSCAccounts.account_config()} | {:error, term()}
  def fetch_gsc_account(account_id) do
    GSCAccounts.fetch_account(account_id)
  end

  @doc """
  Fetch a single GSC account definition, raising when unavailable.
  """
  @spec fetch_gsc_account!(account_id()) :: GSCAccounts.account_config()
  def fetch_gsc_account!(account_id) do
    GSCAccounts.fetch_account!(account_id)
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

  @doc """
  Retrieve the default property for a GSC account.
  """
  @spec gsc_default_property(account_id()) ::
          {:ok, String.t()} | {:error, term()}
  def gsc_default_property(account_id) do
    with {:ok, account} <- GSCAccounts.fetch_account(account_id) do
      setting = Repo.get(AccountSetting, account_id)

      case effective_default_property(setting, account.default_property) do
        nil -> {:error, :missing_property}
        property -> {:ok, property}
      end
    end
  end

  @spec gsc_default_property(Scope.t() | nil, account_id()) ::
          {:ok, String.t()} | {:error, term()}
  def gsc_default_property(%Scope{}, account_id), do: gsc_default_property(account_id)
  def gsc_default_property(nil, account_id), do: gsc_default_property(account_id)

  @spec gsc_default_property!(account_id()) :: String.t()
  def gsc_default_property!(account_id) do
    case gsc_default_property(account_id) do
      {:ok, property} ->
        property

      {:error, reason} ->
        raise ArgumentError,
              "GSC account #{inspect(account_id)} is missing a default property (reason: #{inspect(reason)}). " <>
                "Set one from Settings ▸ Search Console Connections."
    end
  end

  @spec gsc_default_property!(Scope.t() | nil, account_id()) :: String.t()
  def gsc_default_property!(%Scope{}, account_id), do: gsc_default_property!(account_id)
  def gsc_default_property!(nil, account_id), do: gsc_default_property!(account_id)

  @doc """
  Returns the list of Search Console properties available to the given account.
  """
  @spec list_property_options(Scope.t() | nil, account_id()) ::
          {:ok, [map()]} | {:error, term()}
  def list_property_options(scope, account_id) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(scope, account_id),
         {:ok, sites} <- GSCClient.list_sites(account_id) do
      {:ok,
       sites
       |> Enum.map(&build_property_option/1)
       |> Enum.sort_by(&property_option_sort_key/1)}
    end
  end

  @doc """
  Persist the chosen default property for the given account.
  """
  @spec set_default_property(Scope.t() | nil, account_id(), String.t()) ::
          {:ok, AccountSetting.t()} | {:error, term()}
  def set_default_property(scope, account_id, property) do
    with {:ok, account_id} <- normalize_account_id(account_id),
         :ok <- Scope.authorize_account(scope, account_id),
         property when is_binary(property) <- normalize_property(property) do
      upsert_account_setting(account_id, %{default_property: property})
    else
      nil ->
        {:error, :invalid_property}

      {:error, _} = error ->
        error
    end
  end

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

  defp filter_accounts_by_scope(accounts, %Scope{account_ids: account_ids})
       when is_list(account_ids) and account_ids != [] do
    ids = MapSet.new(account_ids)
    Enum.filter(accounts, fn %{id: id} -> MapSet.member?(ids, id) end)
  end

  defp filter_accounts_by_scope(accounts, _scope), do: accounts

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

      effective_property =
        effective_default_property(setting, account.default_property)

      property_source =
        case {normalize_property(setting && setting.default_property),
              normalize_property(account.default_property)} do
          {value, _} when is_binary(value) -> :user
          {_, value} when is_binary(value) -> :config
          _ -> :none
        end

      account
      |> Map.put(:display_name, display_name)
      |> Map.put(:default_property, effective_property)
      |> Map.put(:default_property_source, property_source)
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

  defp effective_default_property(nil, config_property), do: normalize_property(config_property)

  defp effective_default_property(%AccountSetting{} = setting, config_property) do
    normalize_property(setting.default_property) ||
      normalize_property(config_property)
  end

  defp normalize_property(nil), do: nil

  defp normalize_property(property) when is_binary(property) do
    case String.trim(property) do
      "" -> nil
      value -> value
    end
  end

  defp normalize_property(_), do: nil

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
end
