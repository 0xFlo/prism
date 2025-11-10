defmodule GscAnalytics.Backlinks do
  @moduledoc """
  Public API for backlink discovery and analysis using Bing Webmaster Tools.

  This module provides high-level functions for:
  - Fetching backlinks for your verified sites
  - Analyzing competitor backlinks (any site, no verification needed)
  - Tracking new and lost backlinks over time
  - Querying backlink data

  ## Quick Start

      # Fetch backlinks for your site
      Backlinks.sync_for_site("https://yoursite.com")

      # Analyze a competitor
      Backlinks.analyze_competitor("https://competitor.com")

      # List all backlinks
      Backlinks.list_backlinks("https://yoursite.com")

      # Get statistics
      Backlinks.stats("https://yoursite.com")
  """

  alias GscAnalytics.Backlinks.{Bing, Storage}
  require Logger

  @doc """
  Sync backlinks for your verified site from Bing Webmaster Tools.

  Fetches all backlinks and stores them in the database.

  ## Parameters
    - site_url: Your verified domain (e.g., "https://yoursite.com")

  ## Returns
    {:ok, count} or {:error, reason}

  ## Examples
      iex> Backlinks.sync_for_site("https://yoursite.com")
      {:ok, 142}  # 142 backlinks found and stored
  """
  def sync_for_site(site_url) do
    Logger.info("Starting backlink sync for #{site_url}")

    with {:ok, backlinks} <- Bing.Fetcher.fetch_all_backlinks(site_url),
         {:ok, result} <- Storage.store_bing_backlinks(site_url, site_url, backlinks) do
      Logger.info("Successfully synced #{result.inserted} backlinks for #{site_url}")
      {:ok, result.inserted}
    else
      {:error, reason} = error ->
        Logger.error("Failed to sync backlinks for #{site_url}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Analyze competitor backlinks (works for any site, no verification needed).

  Fetches backlinks from Bing and stores them for analysis.

  ## Parameters
    - competitor_url: Domain to analyze (e.g., "https://competitor.com")

  ## Returns
    {:ok, count} or {:error, reason}

  ## Examples
      iex> Backlinks.analyze_competitor("https://competitor.com")
      {:ok, 87}  # 87 backlinks found
  """
  def analyze_competitor(competitor_url) do
    Logger.info("Analyzing competitor backlinks: #{competitor_url}")

    with {:ok, backlinks} <- Bing.Fetcher.fetch_all_backlinks(competitor_url),
         {:ok, result} <- Storage.store_bing_backlinks(competitor_url, competitor_url, backlinks) do
      Logger.info("Successfully analyzed #{result.inserted} backlinks for #{competitor_url}")
      {:ok, result.inserted}
    else
      {:error, reason} = error ->
        Logger.error("Failed to analyze competitor #{competitor_url}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetch backlinks for a specific page (not just the homepage).

  ## Parameters
    - site_url: Domain (e.g., "https://yoursite.com")
    - target_url: Specific page (e.g., "https://yoursite.com/blog/post")

  ## Returns
    {:ok, count} or {:error, reason}

  ## Examples
      iex> Backlinks.sync_for_url("https://yoursite.com", "https://yoursite.com/blog/seo-tips")
      {:ok, 23}
  """
  def sync_for_url(site_url, target_url) do
    Logger.info("Syncing backlinks for specific URL: #{target_url}")

    with {:ok, backlinks} <- Bing.Fetcher.fetch_backlinks_for_url(site_url, target_url),
         {:ok, result} <- Storage.store_bing_backlinks(site_url, target_url, backlinks) do
      Logger.info("Successfully synced #{result.inserted} backlinks for #{target_url}")
      {:ok, result.inserted}
    else
      {:error, reason} = error ->
        Logger.error("Failed to sync backlinks for #{target_url}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Sync backlinks for all verified sites in your Bing Webmaster account.

  ## Returns
    {:ok, %{site_url => count}} or {:error, reason}

  ## Examples
      iex> Backlinks.sync_all_sites()
      {:ok, %{
        "https://site1.com" => 142,
        "https://site2.com" => 87
      }}
  """
  def sync_all_sites do
    Logger.info("Syncing backlinks for all verified sites")

    case Bing.Fetcher.fetch_all_sites_backlinks() do
      {:ok, sites_backlinks} ->
        results =
          Enum.map(sites_backlinks, fn {site_url, backlinks} ->
            case Storage.store_bing_backlinks(site_url, site_url, backlinks) do
              {:ok, result} -> {site_url, result.inserted}
              {:error, _} -> {site_url, 0}
            end
          end)
          |> Map.new()

        {:ok, results}

      {:error, reason} = error ->
        Logger.error("Failed to sync all sites: #{inspect(reason)}")
        error
    end
  end

  @doc """
  List all backlinks for a URL.

  ## Parameters
    - target_url: URL to get backlinks for
    - opts: Keyword list options
      - :data_source - Filter by source ("bing", "ahrefs", etc.)
      - :limit - Max results (default: 100)
      - :order_by - :newest (default) or :oldest

  ## Returns
    [%Backlink{}]

  ## Examples
      iex> Backlinks.list_backlinks("https://yoursite.com")
      [%Backlink{source_url: "...", anchor_text: "..."}, ...]

      iex> Backlinks.list_backlinks("https://yoursite.com", data_source: "bing", limit: 50)
      [...]
  """
  def list_backlinks(target_url, opts \\ []) do
    Storage.list_backlinks(target_url, opts)
  end

  @doc """
  Find new backlinks detected in the last N days.

  ## Parameters
    - target_url: URL to check
    - days: Number of days to look back (default: 7)

  ## Returns
    [%Backlink{}]

  ## Examples
      iex> Backlinks.new_backlinks("https://yoursite.com", 7)
      [%Backlink{...}]
  """
  def new_backlinks(target_url, days \\ 7) do
    Storage.new_backlinks(target_url, days)
  end

  @doc """
  Get backlink statistics for a URL.

  ## Parameters
    - target_url: URL to analyze

  ## Returns
    %{
      total: 100,
      by_source: %{"bing" => 50, "ahrefs" => 50},
      new_7_days: 5,
      new_30_days: 15
    }

  ## Examples
      iex> Backlinks.stats("https://yoursite.com")
      %{total: 142, by_source: %{"bing" => 142}, new_7_days: 5, new_30_days: 15}
  """
  def stats(target_url) do
    Storage.backlink_stats(target_url)
  end

  @doc """
  Get top referring domains for a URL.

  ## Parameters
    - target_url: URL to analyze
    - limit: Max domains to return (default: 10)

  ## Returns
    [{"domain.com", count}, ...]

  ## Examples
      iex> Backlinks.top_referring_domains("https://yoursite.com", 5)
      [{"example.com", 15}, {"another.com", 8}, ...]
  """
  def top_referring_domains(target_url, limit \\ 10) do
    Storage.top_referring_domains(target_url, limit)
  end

  @doc """
  Count total backlinks for a URL.

  ## Parameters
    - target_url: URL to count backlinks for
    - data_source: Optional filter by source

  ## Returns
    integer

  ## Examples
      iex> Backlinks.count("https://yoursite.com")
      142

      iex> Backlinks.count("https://yoursite.com", "bing")
      142
  """
  def count(target_url, data_source \\ nil) do
    Storage.count_backlinks(target_url, data_source)
  end

  @doc """
  Test the Bing API connection and get your verified sites.

  Useful for debugging and confirming API key is working.

  ## Returns
    {:ok, [site_urls]} or {:error, reason}

  ## Examples
      iex> Backlinks.test_connection()
      {:ok, ["https://yoursite.com", "https://another.com"]}
  """
  def test_connection do
    Logger.info("Testing Bing API connection...")

    case Bing.Client.get_user_sites() do
      {:ok, sites} ->
        Logger.info("Successfully connected to Bing API. Found #{length(sites)} verified sites.")
        {:ok, sites}

      {:error, reason} = error ->
        Logger.error("Failed to connect to Bing API: #{inspect(reason)}")
        error
    end
  end
end
