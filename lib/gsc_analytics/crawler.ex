defmodule GscAnalytics.Crawler do
  @moduledoc """
  Web crawling utilities for URL validation and health monitoring.

  This module provides a clean API for checking HTTP status codes,
  following redirects, and validating URL health at scale.

  ## Quick Start

      # Check a single URL
      {:ok, result} = Crawler.check_url("https://example.com")

      # Check multiple URLs concurrently
      {:ok, results} = Crawler.check_batch(["https://example.com", ...])

      # Check all URLs for an account
      {:ok, stats} = Crawler.check_all(account_id: 1, filter: :stale)

      # Subscribe to progress updates
      Crawler.subscribe()

  ## Progress Tracking

  The crawler broadcasts real-time progress via Phoenix PubSub.
  LiveViews can subscribe to receive updates:

      def mount(_params, _session, socket) do
        if connected?(socket), do: Crawler.subscribe()
        {:ok, socket}
      end

      def handle_info({:crawler_progress, %{type: :update, job: job}}, socket) do
        {:noreply, assign(socket, :crawler_job, job)}
      end

  ## Result Structure

  Each check result contains:

      %{
        status: 200,                    # HTTP status code (or nil if error)
        redirect_url: nil,              # Final URL after redirects (or nil)
        redirect_chain: %{              # Full redirect path
          "step_1" => "https://old.com",
          "step_2" => "https://new.com"
        },
        checked_at: ~U[2025-10-09 ...], # Timestamp
        error: nil                      # Error message (or nil if successful)
      }
  """

  alias GscAnalytics.Crawler.{HttpStatus, BatchProcessor, ProgressTracker, Persistence}

  # ============================================================================
  # Single URL Operations
  # ============================================================================

  @doc """
  Check the HTTP status of a single URL.

  Uses GET requests and follows redirects manually to detect 301/302 redirects
  for SEO purposes. Returns the INITIAL status code (e.g., 301) along with the
  final redirect destination.

  ## Options
    - `:timeout` - Request timeout in milliseconds (default: 10_000)
    - `:max_redirects` - Maximum redirect depth (default: 10)

  ## Examples

      iex> Crawler.check_url("https://scrapfly.io")
      {:ok, %{status: 200, redirect_url: nil, ...}}

      iex> Crawler.check_url("https://scrapfly.io/old-page")
      {:ok, %{status: 301, redirect_url: "https://scrapfly.io/new-page", ...}}
  """
  defdelegate check_url(url, opts \\ []), to: HttpStatus

  # ============================================================================
  # Batch Operations
  # ============================================================================

  @doc """
  Check multiple URLs concurrently.

  Processes URLs in parallel with configurable concurrency and timeouts.
  Automatically saves results to the database.

  ## Options
    - `:concurrency` - Number of concurrent requests (default: 15)
    - `:timeout` - Timeout per URL in milliseconds (default: 10_000)
    - `:delay_ms` - Delay between requests in milliseconds (default: 100)
    - `:progress_tracking` - Enable progress tracking (default: true)
    - `:save_results` - Save results to database (default: true)

  ## Examples

      urls = ["https://example.com", "https://example.org"]
      {:ok, results} = Crawler.check_batch(urls, concurrency: 5, delay_ms: 1000)

  ## Returns

      {:ok, [
        {"https://example.com", %{status: 200, ...}},
        {"https://example.org", %{status: 404, ...}}
      ]}
  """
  defdelegate check_batch(urls, opts \\ []), to: BatchProcessor, as: :process_batch

  @doc """
  Check all URLs for an account that need checking.

  Fetches URLs from the database based on filter criteria and checks them
  concurrently. Progress is tracked in real-time via PubSub.

  ## Options
    - `:account_id` - Account ID (default: 1)
    - `:property_id` - Workspace property identifier (UUID)
    - `:property_url` - Property URL to scope URLs
    - `:property_label` - Human-friendly label for UI metadata
    - `:filter` - Which URLs to check:
      - `:all` - Check all URLs
      - `:stale` - Only unchecked or >7 days old (default)
      - `:broken` - Only 4xx/5xx status codes
      - `:redirected` - Only 3xx status codes
    - `:concurrency` - Number of concurrent requests (default: 15)
    - `:delay_ms` - Delay between requests in milliseconds (default: 100)

  ## Examples

      # Check stale URLs (default)
      {:ok, stats} = Crawler.check_all(account_id: 1)

      # Check all broken links
      {:ok, stats} = Crawler.check_all(account_id: 1, filter: :broken)

      # Custom concurrency
      {:ok, stats} = Crawler.check_all(account_id: 1, concurrency: 25)

  ## Returns

      {:ok, %{
        total: 3724,
        checked: 3724,
        status_2xx: 3500,
        status_3xx: 150,
        status_4xx: 50,
        status_5xx: 10,
        errors: 14
      }}
  """
  defdelegate check_all(opts \\ []), to: BatchProcessor, as: :process_all

  # ============================================================================
  # Progress Tracking
  # ============================================================================

  @doc """
  Subscribe to crawler progress events via Phoenix PubSub.

  Receive real-time updates about ongoing check operations.

  ## Events

  - `{:crawler_progress, %{type: :started, job: %{...}}}`
  - `{:crawler_progress, %{type: :update, job: %{...}}}`
  - `{:crawler_progress, %{type: :finished, job: %{...}, stats: %{...}}}`

  ## Example

      def mount(_params, _session, socket) do
        if connected?(socket), do: Crawler.subscribe()
        {:ok, socket}
      end

      def handle_info({:crawler_progress, event}, socket) do
        case event.type do
          :started -> # Handle start
          :update -> # Handle progress update
          :finished -> # Handle completion
        end
      end
  """
  defdelegate subscribe(), to: ProgressTracker

  @doc """
  Get the currently running check job.

  Returns `nil` if no check is in progress.

  ## Example

      case Crawler.current_progress() do
        nil -> IO.puts("No check running")
        progress -> IO.puts("Checking \#{progress.checked}/\#{progress.total_urls} URLs")
      end
  """
  defdelegate current_progress(), to: ProgressTracker, as: :get_current_job

  @doc """
  Get the history of recent check operations.

  Returns up to 50 most recent completed checks.

  ## Example

      history = Crawler.get_history()
      # [%{id: "check-123", total_urls: 3724, checked: 3724, ...}, ...]
  """
  defdelegate get_history(), to: ProgressTracker

  # ============================================================================
  # Persistence
  # ============================================================================

  @doc """
  Manually save a check result to the database.

  Usually not needed as `check_batch/2` and `check_all/1` save automatically.

  ## Example

      {:ok, result} = Crawler.check_url("https://example.com")
      Crawler.save_result("https://example.com", result)
  """
  defdelegate save_result(url, result), to: Persistence
end
