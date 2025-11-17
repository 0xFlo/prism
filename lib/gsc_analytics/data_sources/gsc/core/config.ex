defmodule GscAnalytics.DataSources.GSC.Core.Config do
  @moduledoc """
  Centralized configuration for GSC sync operations.

  This module consolidates all magic numbers and configuration values
  that were previously scattered throughout the codebase. All values
  can be overridden through application configuration.

  ## Configuration Groups

  - **API Limits**: GSC API pagination and rate limits
  - **Sync Behavior**: How sync operations behave
  - **Performance Tuning**: Concurrency and batch sizes
  - **Timeouts**: Various timeout values
  - **Data Aggregation**: Time windows for metrics

  ## Overriding Values

  Values can be overridden in config files:

      config :gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config,
        page_size: 25_000,
        default_batch_size: 10,
        sync_timeout: 45_000
  """

  # ============================================================================
  # API Limits & Constraints
  # ============================================================================

  @doc """
  Maximum rows returned per GSC API request.
  Google Search Console hard limit is 25,000 rows per query.
  """
  def page_size do
    get_config(:page_size, 25_000)
  end

  @doc """
  Number of requests to batch in a single HTTP call.
  Google Batch API supports up to 100 requests per batch.
  """
  def batch_limit do
    get_config(:batch_limit, 100)
  end

  # ============================================================================
  # Sync Behavior Configuration
  # ============================================================================

  @doc """
  Default account ID for single-tenant deployments.
  """
  def default_account_id do
    get_config(:default_account_id, 1)
  end

  @doc """
  Days of data delay in GSC (Google's processing lag).
  GSC data is typically 2-3 days behind.
  """
  def data_delay_days do
    get_config(:data_delay_days, 3)
  end

  @doc """
  Maximum days of historical data to sync.
  GSC API limit is 16 months (approximately 540 days).
  """
  def full_history_days do
    get_config(:full_history_days, 540)
  end

  @doc """
  Number of consecutive empty results before halting backfill.
  Prevents unnecessary API calls when reaching the beginning of data.
  """
  def empty_result_limit do
    get_config(:empty_result_limit, 14)
  end

  @doc """
  Grace period for leading empty results.
  Allows for gaps at the beginning of a site's history.
  """
  def leading_empty_grace_days do
    get_config(:leading_empty_grace_days, 30)
  end

  @doc """
  Maximum days of sync history to keep in memory.
  Used by SyncProgress for tracking sync operations.
  """
  def sync_history_limit do
    get_config(:sync_history_limit, 120)
  end

  # ============================================================================
  # Performance Tuning
  # ============================================================================

  @doc """
  Default number of concurrent requests in a batch.
  Balances API rate limits with performance.
  Increased to 50 to reduce HTTP round-trips while maintaining good throughput.
  With 10 workers, this gives 500 concurrent requests for heavy workloads.
  """
  def default_batch_size do
    get_config(:default_batch_size, 50)
  end

  @doc """
  Number of dates to process in each scheduler chunk.
  Smaller chunks provide more frequent progress updates.
  Increased from 8 to 16 for better parallelization.
  """
  def query_scheduler_chunk_size do
    get_config(:query_scheduler_chunk_size, 16)
  end

  @doc """
  Number of items to process in database batch operations.
  Balances memory usage with database round trips.
  """
  def db_batch_size do
    get_config(:db_batch_size, 100)
  end

  @doc """
  Batch size for time series bulk inserts.
  Prevents hitting PostgreSQL parameter limits (65,535 total parameters).
  With 10 fields per record, 2000 URLs = 20,000 parameters (safe margin).
  Increased to 2000 to reduce database round trips.
  """
  def time_series_batch_size do
    get_config(:time_series_batch_size, 2000)
  end

  @doc """
  Batch size for lifetime stats refresh operations.
  Increased to 5000 to reduce transaction overhead.
  Larger batches significantly improve throughput when deferred to end of sync.
  """
  def lifetime_stats_batch_size do
    get_config(:lifetime_stats_batch_size, 5000)
  end

  @doc """
  Timeout for lifetime stats refresh queries (milliseconds).
  These queries aggregate large slices of gsc_time_series so we give them more time.
  """
  def lifetime_stats_timeout do
    get_config(:lifetime_stats_timeout, 60_000)
  end

  @doc """
  Batch size for query processing operations.
  Used when updating time_series records with query data.
  Increased to 5000 to reduce database round trips and improve throughput.
  """
  def query_batch_size do
    get_config(:query_batch_size, 5000)
  end

  @doc """
  Chunk size for query write operations.
  Smaller than query_batch_size to avoid Postgrex timeouts during heavy upserts.
  Default of 1000 rows per insert keeps operations under the 60s timeout.
  """
  def query_write_chunk_size do
    get_config(:query_write_chunk_size, 1000)
  end

  @doc """
  Timeout for query write operations in milliseconds.
  Longer than default Repo timeout (15s) to accommodate bulk upserts.
  """
  def query_write_timeout do
    get_config(:query_write_timeout, 60_000)
  end

  @doc """
  Maximum number of pending query writer jobs allowed before applying backpressure.
  Prevents pagination workers from filling memory while waiting for DB slots.
  """
  def query_writer_pending_limit do
    get_config(:query_writer_pending_limit, 12)
  end

  @doc """
  Maximum number of concurrent query writer tasks.
  Limits DB connection pool usage during concurrent sync operations.
  With a pool of 40 connections, 3 writers leaves headroom for other operations.
  """
  def query_writer_max_concurrency do
    get_config(:query_writer_max_concurrency, 3)
  end

  @doc """
  Maximum concurrent URL fetches in batch operations.
  Increased to 10 for better parallelism with heavy workloads.
  """
  def max_concurrency do
    get_config(:max_concurrency, 10)
  end

  @doc """
  Maximum number of pagination jobs allowed in the coordinator queue.
  """
  def max_queue_size do
    get_config(:max_queue_size, 1_000)
  end

  @doc """
  Maximum number of in-flight batches pending result processing.

  IMPORTANT: Must be >= batch_size * max_concurrency * 2 to avoid backpressure.
  With batch_size=50 and max_concurrency=10, minimum is 500, but we use 800
  to ensure workers never wait for in-flight slots. Higher value = better parallelism.
  """
  def max_in_flight do
    get_config(:max_in_flight, 800)
  end

  # ============================================================================
  # Retry Configuration
  # ============================================================================

  @doc """
  Maximum number of retry attempts for API calls.
  """
  def max_retries do
    get_config(:max_retries, 3)
  end

  @doc """
  Base delay for exponential backoff in milliseconds.
  """
  def retry_delay do
    get_config(:retry_delay, 1_000)
  end

  # ============================================================================
  # Timeouts
  # ============================================================================

  @doc """
  Default HTTP request timeout in milliseconds.
  Increased from 30s to 45s to accommodate larger batch sizes (50 requests/batch).
  """
  def http_timeout do
    get_config(:http_timeout, 45_000)
  end

  @doc """
  Agent coordination timeout in milliseconds.
  Used for StreamCoordinator operations.
  """
  def agent_timeout do
    get_config(:agent_timeout, 5_000)
  end

  @doc """
  Extended timeout for complex Agent operations.
  """
  def agent_extended_timeout do
    get_config(:agent_extended_timeout, 10_000)
  end

  @doc """
  Retry delay for token fetch failures in milliseconds.
  """
  def token_retry_delay do
    get_config(:token_retry_delay, 1_000)
  end

  @doc """
  Retry delay after token refresh failure in seconds.
  """
  def token_refresh_retry_delay do
    get_config(:token_refresh_retry_delay, 30)
  end

  @doc """
  Buffer time before token expiry to trigger refresh (in seconds).
  """
  def token_refresh_buffer do
    get_config(:token_refresh_buffer, 600)
  end

  # ============================================================================
  # Data Aggregation
  # ============================================================================

  @doc """
  Default number of days to aggregate for performance metrics.
  """
  def performance_aggregation_days do
    get_config(:performance_aggregation_days, 30)
  end

  @doc """
  Threshold for slow Agent coordination warning (milliseconds).
  Operations taking longer than this will log a warning.
  """
  def slow_agent_threshold do
    get_config(:slow_agent_threshold, 1_000)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp get_config(key, default) do
    Application.get_env(:gsc_analytics, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
