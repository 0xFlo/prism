defmodule GscAnalytics.DataSources.GSC.AccountsHelper do
  @moduledoc """
  Helper functions for managing and exploring GSC accounts and their properties.

  ## Usage in IEx:

      iex> alias GscAnalytics.DataSources.GSC.AccountsHelper
      iex> AccountsHelper.list_available_properties(1)
      iex> AccountsHelper.list_all_properties()
      iex> AccountsHelper.check_property_access(2, "sc-domain:example.com")
  """

  alias GscAnalytics.DataSources.GSC.Core.Client
  alias GscAnalytics.DataSources.GSC.Accounts

  @doc """
  List all GSC properties accessible by a specific account.

  ## Examples

      iex> AccountsHelper.list_available_properties(1)

      Account: Scrapfly (ID: 1)
      Configured property: sc-domain:scrapfly.io

      Available GSC properties:
      1. sc-domain:scrapfly.io (siteFullUser) ✓ Configured
      2. sc-domain:webscraping.fyi (siteFullUser)
      3. sc-domain:scrapeway.com (siteFullUser)

      {:ok, 3}
  """
  def list_available_properties(account_id) do
    with {:ok, account} <- Accounts.fetch_account(account_id),
         {:ok, sites} <- Client.list_sites(account_id) do

      IO.puts("\nAccount: #{account.name} (ID: #{account.id})")
      IO.puts("Configured property: #{account.default_property || "(none configured)"}")
      IO.puts("\nAvailable GSC properties:")

      if Enum.empty?(sites) do
        IO.puts("  (No properties found - check service account permissions)")
        {:ok, 0}
      else
        sites
        |> Enum.with_index(1)
        |> Enum.each(fn {site, index} ->
          configured = if site.site_url == account.default_property, do: " ✓ Configured", else: ""
          IO.puts("#{index}. #{site.site_url} (#{site.permission_level})#{configured}")
        end)

        {:ok, length(sites)}
      end
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all GSC properties for all configured accounts.
  """
  def list_all_properties do
    accounts = Accounts.list_accounts()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("GSC Properties by Account")
    IO.puts(String.duplicate("=", 60))

    results =
      Enum.map(accounts, fn account ->
        IO.puts("")
        result = list_available_properties(account.id)
        IO.puts(String.duplicate("-", 40))
        result
      end)

    # Summary
    total_accounts = length(accounts)
    successful = Enum.count(results, fn r -> match?({:ok, _}, r) end)

    IO.puts("\nSummary: #{successful}/#{total_accounts} accounts accessible")
    results
  end

  @doc """
  Check if a specific account has access to a property.

  ## Examples

      iex> AccountsHelper.check_property_access(1, "sc-domain:scrapfly.io")
      ✓ Account 1 has access to sc-domain:scrapfly.io (siteFullUser)
      {:ok, true}

      iex> AccountsHelper.check_property_access(2, "sc-domain:example.com")
      ✗ Account 2 does NOT have access to sc-domain:example.com
      {:ok, false}
  """
  def check_property_access(account_id, property_url) do
    with {:ok, account} <- Accounts.fetch_account(account_id),
         {:ok, sites} <- Client.list_sites(account_id) do

      site = Enum.find(sites, fn s -> s.site_url == property_url end)

      if site do
        IO.puts("✓ Account #{account.id} has access to #{property_url} (#{site.permission_level})")
        {:ok, true}
      else
        IO.puts("✗ Account #{account.id} does NOT have access to #{property_url}")
        IO.puts("  Available properties: #{sites |> Enum.map(& &1.site_url) |> Enum.join(", ")}")
        {:ok, false}
      end
    else
      {:error, reason} ->
        IO.puts("Error checking access: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Suggest which property to use for an account based on available access.

  ## Examples

      iex> AccountsHelper.suggest_property(2)

      Suggested properties for Account 2:
      1. sc-domain:example.com (domain property - recommended)
      2. https://www.example.com/ (URL property)

      To update: Accounts.update_account(account, %{gsc_property: "sc-domain:example.com"})
  """
  def suggest_property(account_id) do
    with {:ok, account} <- Accounts.fetch_account(account_id),
         {:ok, sites} <- Client.list_sites(account_id) do

      if Enum.empty?(sites) do
        IO.puts("\nNo properties available for Account #{account.id}")
        IO.puts("Please ensure the service account (#{account.service_account_file}) has access to GSC properties.")
        {:ok, []}
      else
        IO.puts("\nSuggested properties for Account #{account.id}:")

        # Prefer domain properties over URL properties
        domain_props = Enum.filter(sites, fn s -> String.starts_with?(s.site_url, "sc-domain:") end)
        url_props = Enum.filter(sites, fn s -> String.starts_with?(s.site_url, "http") end)

        suggestions =
          (domain_props ++ url_props)
          |> Enum.with_index(1)
          |> Enum.map(fn {site, index} ->
            type = if String.starts_with?(site.site_url, "sc-domain:"),
                   do: "domain property - recommended",
                   else: "URL property"
            IO.puts("#{index}. #{site.site_url} (#{type})")
            site.site_url
          end)

        IO.puts("\nTo update configuration, add to config/config.exs:")
        IO.puts("  config :gsc_analytics, :gsc_accounts,")
        IO.puts("    %{#{account.id} => %{default_property: \"#{List.first(suggestions)}\"}}")

        {:ok, suggestions}
      end
    else
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Analyze property types across all accounts (domain vs URL properties).
  """
  def analyze_property_types do
    accounts = Accounts.list_accounts()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Property Type Analysis")
    IO.puts(String.duplicate("=", 60))

    all_sites =
      accounts
      |> Enum.flat_map(fn account ->
        case Client.list_sites(account.id) do
          {:ok, sites} -> sites
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.site_url)

    domain_props = Enum.filter(all_sites, fn s -> String.starts_with?(s.site_url, "sc-domain:") end)
    url_props = Enum.filter(all_sites, fn s -> String.starts_with?(s.site_url, "http") end)

    IO.puts("\nDomain Properties (#{length(domain_props)}):")
    Enum.each(domain_props, fn site ->
      domain = String.replace_prefix(site.site_url, "sc-domain:", "")
      IO.puts("  • #{domain} (#{site.permission_level})")
    end)

    IO.puts("\nURL Properties (#{length(url_props)}):")
    Enum.each(url_props, fn site ->
      uri = URI.parse(site.site_url)
      IO.puts("  • #{uri.host}#{uri.path} (#{site.permission_level})")
    end)

    IO.puts("\nSummary:")
    IO.puts("  Domain properties: #{length(domain_props)} (recommended for complete data)")
    IO.puts("  URL properties: #{length(url_props)} (limited to specific paths)")

    %{
      domain_properties: length(domain_props),
      url_properties: length(url_props),
      total: length(all_sites)
    }
  end
end