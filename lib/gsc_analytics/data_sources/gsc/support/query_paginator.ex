defmodule GscAnalytics.DataSources.GSC.Support.QueryPaginator do
  @moduledoc """
  Manages paginated query fetching with ordered result processing.

  This module consolidates pagination logic that was previously spread across
  QueryScheduler, StreamCoordinator, and Pagination modules. It handles:

  - Pagination queue management for multiple dates
  - Ordered result processing to maintain consistency
  - Streaming callbacks for real-time data processing
  - Automatic page size calculation and next page detection
  """

  require Logger
  alias GscAnalytics.DataSources.GSC.Core.Config

  alias GscAnalytics.DataSources.GSC.Support.{
    ConcurrentBatchWorker,
    QueryCoordinator,
    RateLimiter
  }

  @page_size 25_000
  @default_batch_size 8

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Fetch all queries for multiple dates with automatic pagination.

  ## Options

    - `:batch_size` - Number of concurrent requests (default: 8)
    - `:on_complete` - Callback function for streaming results
    - `:dimensions` - Query dimensions (default: ["page", "query"])
    - `:operation` - Operation name for logging
    - `:client` - Client module to use
    - `:max_concurrency` - Number of concurrent workers (default: Config.max_concurrency/0)
    - `:max_queue_size` / `:max_in_flight` - Coordinator backpressure limits
    - `:rate_limiter` - Module implementing `check_rate/3` (default: RateLimiter)

  ## Returns

    - `{:ok, results_map, total_api_calls, http_batch_count}` - Success
    - `{:error, reason, partial_results, api_calls, batch_count}` - Failure with partial data
    - `{:halt, reason, partial_results, api_calls, batch_count}` - User-initiated halt
  """
  @spec fetch_all_queries(pos_integer(), String.t(), [Date.t()], keyword()) ::
          {:ok, map(), non_neg_integer(), non_neg_integer()}
          | {:error, term(), map(), non_neg_integer(), non_neg_integer()}
          | {:halt, term(), map(), non_neg_integer(), non_neg_integer()}
  def fetch_all_queries(account_id, site_url, dates, opts \\ [])

  def fetch_all_queries(_account_id, _site_url, [], _opts) do
    {:ok, %{}, 0, 0}
  end

  def fetch_all_queries(account_id, site_url, dates, opts) when is_list(dates) do
    opts = Keyword.put_new(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, Config.max_concurrency())

    fetch_all_queries_concurrent(account_id, site_url, dates, opts, max_concurrency)
  end

  defp fetch_all_queries_concurrent(account_id, site_url, dates, opts, max_concurrency) do
    batch_size = Keyword.fetch!(opts, :batch_size)
    client = Keyword.get(opts, :client, client_module())
    operation = Keyword.get(opts, :operation, "fetch_all_queries_batch")
    dimensions = Keyword.get(opts, :dimensions, ["page", "query"])
    on_complete = Keyword.get(opts, :on_complete)
    rate_limiter = Keyword.get(opts, :rate_limiter, RateLimiter)

    coordinator_opts = [
      account_id: account_id,
      site_url: site_url,
      dates: dates,
      on_complete: on_complete,
      max_queue_size: Keyword.get(opts, :max_queue_size, Config.max_queue_size()),
      max_in_flight: Keyword.get(opts, :max_in_flight, Config.max_in_flight())
    ]

    with {:ok, coordinator} <- QueryCoordinator.start_link(coordinator_opts) do
      worker_opts = [
        account_id: account_id,
        site_url: site_url,
        operation: operation,
        dimensions: dimensions,
        batch_size: batch_size,
        max_concurrency: max_concurrency,
        client: client,
        rate_limiter: rate_limiter
      ]

      case await_worker_tasks(ConcurrentBatchWorker.start_workers(coordinator, worker_opts)) do
        :ok ->
          finalize_concurrent(coordinator)

        {:error, reason} ->
          QueryCoordinator.halt(coordinator, {:worker_exit, reason})
          finalize_concurrent(coordinator)
      end
    else
      {:error, reason} ->
        {:error, reason, %{}, 0, 0}
    end
  end

  defp finalize_concurrent(coordinator) do
    try do
      coordinator
      |> QueryCoordinator.finalize()
      |> format_coordinator_result()
    after
      GenServer.stop(coordinator, :normal)
    end
  end

  defp await_worker_tasks(tasks) do
    try do
      Task.await_many(tasks, :infinity)
      :ok
    catch
      :exit, reason ->
        {:error, reason}
    after
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))
    end
  end

  defp format_coordinator_result({:ok, _reason, results, total_calls, http_batches}) do
    {:ok, results, total_calls, http_batches}
  end

  defp format_coordinator_result({:halt, reason, results, total_calls, http_batches}) do
    {:halt, reason, results, total_calls, http_batches}
  end

  defp format_coordinator_result({:error, reason, results, total_calls, http_batches}) do
    {:error, reason, results, total_calls, http_batches}
  end


  @doc """
  Check if we need to fetch the next page of results.
  """
  @spec needs_next_page?(list()) :: boolean()
  def needs_next_page?(rows) when is_list(rows), do: length(rows) >= @page_size

  @doc """
  Calculate the next starting row offset for pagination.
  """
  @spec next_start_row(non_neg_integer()) :: non_neg_integer()
  def next_start_row(current_start_row)
      when is_integer(current_start_row) and current_start_row >= 0 do
    current_start_row + @page_size
  end

  @doc """
  Get the configured page size for GSC API requests.
  """
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size


  defp client_module do
    Application.get_env(:gsc_analytics, :gsc_client, GscAnalytics.DataSources.GSC.Core.Client)
  end
end
