defmodule GscAnalytics.Accounts do
  @moduledoc """
  Convenience helpers for working with configured Google Search Console accounts.

  This module bridges application-level defaults with the configuration-driven
  account registry exposed via `GscAnalytics.DataSources.GSC.Accounts`.
  """

  alias GscAnalytics.DataSources.GSC.Accounts, as: GSCAccounts
  alias GscAnalytics.DataSources.GSC.Core.Config, as: GSCConfig

  @type account_id :: GSCAccounts.account_id()

  @doc """
  Returns the configured default GSC account identifier.
  """
  @spec default_account_id() :: account_id()
  def default_account_id do
    GSCConfig.default_account_id()
  end

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
  Proxy to the configured GSC account registry.
  """
  @spec list_gsc_accounts(keyword()) :: [GSCAccounts.account_config()]
  def list_gsc_accounts(opts \\ []) do
    GSCAccounts.list_accounts(opts)
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
    GSCAccounts.account_options()
  end

  @doc """
  Retrieve the default property for a GSC account.
  """
  @spec gsc_default_property(account_id()) ::
          {:ok, String.t()} | {:error, term()}
  def gsc_default_property(account_id) do
    GSCAccounts.default_property(account_id)
  end

  @spec gsc_default_property!(account_id()) :: String.t()
  def gsc_default_property!(account_id) do
    GSCAccounts.default_property!(account_id)
  end
end
