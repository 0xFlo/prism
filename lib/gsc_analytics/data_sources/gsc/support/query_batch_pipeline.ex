defmodule GscAnalytics.DataSources.GSC.Support.QueryBatchPipeline do
  @moduledoc """
  Broadway pipeline that replaces the legacy ConcurrentBatchWorker for query fetching.
  """

  use Broadway

  require Logger

  alias Broadway.Message
  alias GscAnalytics.DataSources.GSC.Core.Config

  alias GscAnalytics.DataSources.GSC.Support.{
    DeadLetter,
    PipelineRetry,
    QueryBatchProducer,
    QueryCoordinator,
    RateLimiter
  }

  def run(opts) do
    name =
      Keyword.get(opts, :name) ||
        Module.concat(__MODULE__, :"Pipeline#{System.unique_integer([:positive])}")

    owner = self()

    broadway_opts = [
      name: name,
      context: %{
        coordinator: Keyword.fetch!(opts, :coordinator),
        account_id: Keyword.fetch!(opts, :account_id),
        site_url: Keyword.fetch!(opts, :site_url),
        client: Keyword.fetch!(opts, :client),
        operation: Keyword.get(opts, :operation, "fetch_all_queries_batch"),
        owner: owner,
        backpressure_sleep_ms: Keyword.get(opts, :backpressure_sleep_ms, 50),
        idle_sleep_ms: Keyword.get(opts, :idle_sleep_ms, 50),
        rate_limiter: Keyword.get(opts, :rate_limiter, RateLimiter)
      },
      producer: [
        module:
          {QueryBatchProducer,
           [
             coordinator: Keyword.fetch!(opts, :coordinator),
             batch_size: Keyword.fetch!(opts, :batch_size),
             owner: owner,
             retry_sleep_ms: Keyword.get(opts, :retry_sleep_ms, 50)
           ]}
      ],
      processors: [
        fetchers: [
          concurrency: Keyword.get(opts, :max_concurrency, Config.max_concurrency())
        ]
      ]
    ]

    {:ok, pid} = Broadway.start_link(__MODULE__, broadway_opts)
    ref = Process.monitor(pid)

    result =
      receive do
        {:query_pipeline_complete, status} -> status
        {:DOWN, ^ref, _, _, reason} -> {:error, reason}
      end

    :ok = Broadway.stop(name)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      0 -> :ok
    end

    result
  end

  @impl true
  def handle_message(_, %Message{data: batch} = message, context) when is_list(batch) do
    case fetch_batch(batch, context) do
      :ok ->
        message

      {:error, reason} ->
        QueryCoordinator.halt(context.coordinator, reason)
        send(context.owner, {:query_pipeline_complete, {:error, reason}})
        message
    end
  end

  defp fetch_batch([], _context), do: :ok

  defp fetch_batch(batch, context) do
    case perform_http_batch(batch, context) do
      {:ok, entries, http_batch_count} ->
        QueryCoordinator.submit_results(context.coordinator, %{
          entries: entries,
          http_batches: http_batch_count
        })

        :ok

      {:error, reason} ->
        Logger.error("Query batch failed: #{inspect(reason)}")
        entries = Enum.map(batch, fn {date, start_row} -> {:error, date, start_row, reason} end)

        QueryCoordinator.submit_results(context.coordinator, %{
          entries: entries,
          http_batches: 0
        })

        DeadLetter.put(:query_pipeline, %{
          site_url: context.site_url,
          account_id: context.account_id,
          reason: inspect(reason),
          batch: Enum.map(batch, fn {date, start_row} -> %{date: date, start_row: start_row} end)
        })

        {:error, reason}
    end
  end

  defp perform_http_batch(batch, context) do
    requests = build_batch_requests(context.site_url, batch, context.operation)
    start = System.monotonic_time(:microsecond)

    result =
      PipelineRetry.retry(
        fn ->
          with :ok <- check_rate(context, length(batch)),
               {:ok, responses, http_batch_count} <-
                 context.client.fetch_query_batch(context.account_id, requests, context.operation) do
            response_map = Map.new(responses, fn part -> {part.id, part} end)
            entries = Enum.map(batch, &build_entry(&1, response_map))
            {:ok, {entries, http_batch_count}}
          else
            {:error, reason} -> {:error, reason}
          end
        end,
        Config.max_retries(),
        Config.retry_delay()
      )

    duration = System.monotonic_time(:microsecond) - start
    emit_batch_metrics(context, length(batch), duration, result)

    case result do
      {:ok, {entries, http_batch_count}} -> {:ok, entries, http_batch_count}
      {:error, reason} -> {:error, reason}
    end
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

  defp build_batch_requests(site_url, batch, operation) do
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
          "dimensions" => ["page", "query"],
          "rowLimit" => GscAnalytics.DataSources.GSC.Support.QueryPaginator.page_size(),
          "startRow" => start_row,
          "dataState" => "final"
        },
        metadata: %{date: date_string, start_row: start_row, operation: operation}
      }
    end)
  end

  defp check_rate(%{rate_limiter: nil}, _count), do: :ok

  defp check_rate(%{rate_limiter: module} = context, count) do
    case module.check_rate(context.account_id, context.site_url, count) do
      :ok -> :ok
      {:error, :rate_limited, wait_ms} -> {:error, {:rate_limited, wait_ms}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp request_id(date, start_row) do
    Date.to_iso8601(date) <> ":" <> Integer.to_string(start_row)
  end

  defp emit_batch_metrics(context, batch_size, duration_us, result) do
    metadata = %{
      account_id: context.account_id,
      site_url: context.site_url,
      status: result_status(result)
    }

    measurements = %{
      duration_ms: System.convert_time_unit(duration_us, :microsecond, :millisecond),
      batch_size: batch_size
    }

    :telemetry.execute([:gsc_analytics, :query_batch], measurements, metadata)
  end

  defp result_status({:ok, _entries, _count}), do: :ok
  defp result_status(_), do: :error
end
