defmodule GscAnalytics.DataSources.GSC.Support.ConcurrentBatchWorker do
  @moduledoc """
  Concurrent worker pool that pulls pagination batches from the QueryCoordinator,
  enforces rate limits, and streams HTTP batch results back to the coordinator.
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Support.{QueryCoordinator, QueryPaginator, RateLimiter}

  @telemetry_prefix [:gsc_analytics, :worker]

  @default_backpressure_sleep 50
  @default_idle_sleep 50

  @doc """
  Starts asynchronous worker tasks.

  Expected options:
    * `:account_id`
    * `:site_url`
    * `:operation`
    * `:dimensions`
    * `:batch_size`
    * `:max_concurrency`
    * `:client` (defaults to configured GSC client)
    * `:backpressure_sleep_ms`
    * `:idle_sleep_ms`
  """
  @spec start_workers(pid(), keyword()) :: [Task.t()]
  def start_workers(coordinator, opts) do
    account_id = Keyword.fetch!(opts, :account_id)
    site_url = Keyword.fetch!(opts, :site_url)
    operation = Keyword.fetch!(opts, :operation)
    dimensions = Keyword.fetch!(opts, :dimensions)
    batch_size = Keyword.fetch!(opts, :batch_size)
    max_concurrency = Keyword.fetch!(opts, :max_concurrency)
    client = Keyword.get(opts, :client, client_module())
    rate_limiter = Keyword.get(opts, :rate_limiter, RateLimiter)
    backpressure_sleep = Keyword.get(opts, :backpressure_sleep_ms, @default_backpressure_sleep)
    idle_sleep = Keyword.get(opts, :idle_sleep_ms, @default_idle_sleep)

    Enum.map(1..max_concurrency, fn worker_id ->
      Task.async(fn ->
        worker_loop(
          coordinator,
          %{
            account_id: account_id,
            site_url: site_url,
            operation: operation,
            dimensions: dimensions,
            batch_size: batch_size,
            worker_id: worker_id,
            client: client,
            rate_limiter: rate_limiter,
            backpressure_sleep_ms: backpressure_sleep,
            idle_sleep_ms: idle_sleep
          }
        )
      end)
    end)
  end

  defp worker_loop(coordinator, state) do
    case QueryCoordinator.take_batch(coordinator, state.batch_size) do
      {:ok, batch} ->
        handle_batch(coordinator, batch, state)

      {:backpressure, reason} ->
        Logger.debug("Worker #{state.worker_id} backing off due to #{inspect(reason)}")
        Process.sleep(state.backpressure_sleep_ms)
        worker_loop(coordinator, state)

      :pending ->
        Process.sleep(state.idle_sleep_ms)
        worker_loop(coordinator, state)

      :no_more_work ->
        :ok

      {:halted, reason} ->
        Logger.debug("Worker #{state.worker_id} stopping, coordinator halted: #{inspect(reason)}")
        :ok
    end
  end

  defp handle_batch(coordinator, batch, state) do
    case fetch_batch(batch, state) do
      {:ok, entries, http_batch_count} ->
        QueryCoordinator.submit_results(coordinator, %{
          entries: entries,
          http_batches: http_batch_count
        })

        if QueryCoordinator.halted?(coordinator) do
          :ok
        else
          worker_loop(coordinator, state)
        end

      {:rate_limited, wait_ms} ->
        Logger.warning("Worker #{state.worker_id} rate limited; retrying in #{wait_ms}ms")
        QueryCoordinator.requeue_batch(coordinator, batch)
        Process.sleep(wait_ms)
        worker_loop(coordinator, state)

      {:error, reason} ->
        Logger.error("Worker #{state.worker_id} failed batch: #{inspect(reason)}")
        entries = Enum.map(batch, fn {date, start_row} -> {:error, date, start_row, reason} end)
        QueryCoordinator.submit_results(coordinator, %{entries: entries, http_batches: 0})
        :ok
    end
  end

  defp fetch_batch(batch, state) do
    case state.rate_limiter.check_rate(state.account_id, state.site_url, length(batch)) do
      :ok ->
        perform_http_batch(batch, state)

      {:error, :rate_limited, wait_ms} ->
        {:rate_limited, wait_ms}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_http_batch(batch, state) do
    requests = build_batch_requests(state.site_url, batch, state.operation, state.dimensions)
    start = System.monotonic_time(:microsecond)

    result =
      case state.client.fetch_query_batch(state.account_id, requests, state.operation) do
        {:ok, responses, http_batch_count} ->
          response_map = Map.new(responses, fn part -> {part.id, part} end)
          entries = Enum.map(batch, &build_entry(&1, response_map))
          {:ok, entries, http_batch_count}

        {:error, reason} ->
          {:error, reason}
      end

    duration = System.monotonic_time(:microsecond) - start
    emit_worker_batch_metrics(state, length(batch), duration, result)
    result
  end

  defp build_entry({date, start_row}, response_map) do
    id = request_id(date, start_row)

    case Map.fetch(response_map, id) do
      {:ok, part} when part.status < 400 ->
        {:ok, date, start_row, part}

      {:ok, part} ->
        {:error, date, start_row, {:http_error, part.status, part.raw_body}}

      :error ->
        {:error, date, start_row, :missing_response}
    end
  end

  defp build_batch_requests(site_url, batch, operation, dimensions) do
    encoded_site = URI.encode_www_form(site_url)
    path = "/webmasters/v3/sites/#{encoded_site}/searchAnalytics/query"

    Enum.map(batch, fn {date, start_row} ->
      date_string = Date.to_iso8601(date)

      %{
        id: request_id(date, start_row),
        site_url: site_url,
        method: :post,
        path: path,
        body: %{
          "startDate" => date_string,
          "endDate" => date_string,
          "dimensions" => dimensions,
          "rowLimit" => QueryPaginator.page_size(),
          "startRow" => start_row,
          "dataState" => "final"
        },
        metadata: %{date: date_string, start_row: start_row, operation: operation}
      }
    end)
  end

  defp request_id(date, start_row) do
    Date.to_iso8601(date) <> ":" <> Integer.to_string(start_row)
  end

  defp client_module do
    Application.get_env(:gsc_analytics, :gsc_client, GscAnalytics.DataSources.GSC.Core.Client)
  end

  defp emit_worker_batch_metrics(state, batch_size, duration_us, result) do
    metadata = %{
      worker_id: state.worker_id,
      account_id: state.account_id,
      site_url: state.site_url,
      status: result_status(result)
    }

    measurements = %{
      duration_ms: System.convert_time_unit(duration_us, :microsecond, :millisecond),
      batch_size: batch_size
    }

    :telemetry.execute(@telemetry_prefix ++ [:batch], measurements, metadata)
  end

  defp result_status({:ok, _entries, _count}), do: :ok
  defp result_status(_), do: :error
end
