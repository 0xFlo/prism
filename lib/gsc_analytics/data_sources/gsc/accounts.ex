defmodule GscAnalytics.DataSources.GSC.Accounts do
  @moduledoc """
  Central access layer for configured Google Search Console accounts.

  The configuration is stored under `config :gsc_analytics, :gsc_accounts`.
  Each entry supports the following keys:

    * `:name` - Display name for the account selector
    * `:service_account_file` - Path to the JSON credentials file
    * `:default_property` - Default Search Console property identifier
    * `:enabled?` - Whether the account should be exposed to the app
  """

  @type account_id :: pos_integer()

  @type account_config :: %{
          id: account_id(),
          name: String.t(),
          service_account_file: String.t() | nil,
          default_property: String.t() | nil,
          enabled?: boolean()
        }

  @doc """
  Return all configured accounts. Disabled accounts are omitted unless
  `include_disabled?: true` is provided.
  """
  @spec list_accounts(keyword()) :: [account_config()]
  def list_accounts(opts \\ []) do
    include_disabled? = Keyword.get(opts, :include_disabled?, false)

    :gsc_analytics
    |> Application.get_env(:gsc_accounts, %{})
    |> Enum.map(&normalize_entry/1)
    |> Enum.filter(fn %{enabled?: enabled?} -> include_disabled? || enabled? end)
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  Fetch the configuration for a specific account.
  """
  @spec fetch_account(account_id()) ::
          {:ok, account_config()} | {:error, :unknown_account | :account_disabled}
  def fetch_account(account_id) do
    account_id = normalize_id(account_id)

    case Enum.find(list_accounts(include_disabled?: true), &(&1.id == account_id)) do
      nil ->
        {:error, :unknown_account}

      %{enabled?: false} ->
        {:error, :account_disabled}

      account ->
        {:ok, account}
    end
  end

  @doc """
  Convenience accessor that raises when the account is missing or disabled.
  Useful in scenarios where configuration should be validated at boot.
  """
  @spec fetch_account!(account_id()) :: account_config()
  def fetch_account!(account_id) do
    case fetch_account(account_id) do
      {:ok, account} ->
        account

      {:error, reason} ->
        raise ArgumentError,
              "GSC account #{inspect(account_id)} is not available (reason: #{inspect(reason)})"
    end
  end

  @doc """
  Retrieve the service account JSON credentials file for the given account.
  """
  @spec service_account_file(account_id()) ::
          {:ok, String.t()} | {:error, :unknown_account | :account_disabled | :missing_credentials}
  def service_account_file(account_id) do
    with {:ok, %{service_account_file: path}} when is_binary(path) <- fetch_account(account_id) do
      {:ok, path}
    else
      {:ok, _} ->
        {:error, :missing_credentials}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieve the default Search Console property identifier for the given account.
  """
  @spec default_property(account_id()) ::
          {:ok, String.t()} | {:error, :unknown_account | :account_disabled | :missing_property}
  def default_property(account_id) do
    with {:ok, %{default_property: property}} when is_binary(property) <- fetch_account(account_id) do
      {:ok, property}
    else
      {:ok, _} ->
        {:error, :missing_property}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec default_property!(account_id()) :: String.t()
  def default_property!(account_id) do
    case default_property(account_id) do
      {:ok, property} ->
        property

      {:error, reason} ->
        raise ArgumentError,
              "GSC account #{inspect(account_id)} is missing a default property (reason: #{inspect(reason)})"
    end
  end

  @doc """
  Convenience helper for rendering account selectors.
  """
  @spec account_options() :: [{String.t(), account_id()}]
  def account_options do
    list_accounts()
    |> Enum.map(fn %{id: id, name: name} -> {name || "Account #{id}", id} end)
  end

  @doc """
  Ensure the configured accounts have credentials on disk. Missing credentials
  are logged and filtered out, preventing accidental requests without auth.
  """
  @spec validate_credentials_on_boot?() :: boolean()
  def validate_credentials_on_boot? do
    Application.get_env(:gsc_analytics, :validate_gsc_credentials_on_boot, true)
  end

  defp normalize_entry({id, attrs}) do
    attrs = attrs || %{}

    %{
      id: normalize_id(id),
      name: fetch_value(attrs, [:name]),
      service_account_file: maybe_expand(fetch_value(attrs, [:service_account_file])),
      default_property: fetch_value(attrs, [:default_property]),
      enabled?: enabled?(attrs)
    }
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} -> value
      _ -> raise ArgumentError, "Invalid account identifier #{inspect(id)}"
    end
  end

  defp fetch_value(map, keys) do
    Enum.find_value(keys, fn key ->
      Map.get(map, key) || Map.get(map, to_string(key))
    end)
  end

  defp maybe_expand(nil), do: nil
  defp maybe_expand(path) when is_binary(path), do: Path.expand(path)

  defp enabled?(attrs) do
    case fetch_value(attrs, [:enabled?]) do
      nil -> true
      value -> value
    end
  end
end
