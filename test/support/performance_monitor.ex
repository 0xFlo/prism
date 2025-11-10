defmodule GscAnalytics.Test.PerformanceMonitor do
  @moduledoc """
  Real-time performance monitoring with telemetry.
  Tracks API calls, database queries, and system metrics.

  ## Features

  - **Database Monitoring**: Query count, timing, throughput
  - **API Monitoring**: GSC API calls, response times, rate limiting
  - **Sync Monitoring**: URL processing throughput, batch efficiency
  - **Memory Profiling**: Process, ETS, binary, and total memory
  - **System Metrics**: Process count, scheduler utilization
  - **Real-time Tracking**: Updates continuously via telemetry

  ## Basic Usage

      setup do
        PerformanceMonitor.start()
        on_exit(fn -> PerformanceMonitor.stop() end)
        :ok
      end

      test "my test" do
        # ... run code ...

        metrics = PerformanceMonitor.get_metrics()
        assert metrics.database.query_count < 100
        assert metrics.database.avg_time_ms < 50
      end

  ## Memory Profiling

      test "memory efficiency" do
        initial = PerformanceMonitor.get_metrics()

        # Run memory-intensive operation
        process_large_dataset()

        final = PerformanceMonitor.get_metrics()

        growth_mb = (final.memory.total_memory -
                     initial.memory.total_memory) / 1_048_576

        assert growth_mb < 100, "Excessive memory growth: \#{growth_mb} MB"

        # Check for memory leaks
        :erlang.garbage_collect()
        after_gc = PerformanceMonitor.get_metrics()

        leaked_mb = (after_gc.memory.total_memory -
                     initial.memory.total_memory) / 1_048_576
        assert leaked_mb < 10, "Possible memory leak: \#{leaked_mb} MB"
      end

  ## Throughput Testing

      test "sync throughput" do
        PerformanceMonitor.reset()

        # Process URLs
        process_urls(1000)

        metrics = PerformanceMonitor.get_metrics()

        # Check throughput
        throughput = metrics.sync.urls_per_second
        assert throughput > 500, "Low throughput: \#{throughput} URLs/sec"

        # Check efficiency
        efficiency = 1000 / metrics.database.query_count
        assert efficiency > 10, "Poor query efficiency: \#{efficiency} URLs/query"
      end

  ## Metrics Structure

      %{
        elapsed_seconds: 10.5,                    # Time since monitoring started

        database: %{
          query_count: 100,                       # Total database queries
          total_time_ms: 250.0,                   # Total time in database
          avg_time_ms: 2.5,                       # Average query time
          max_time_ms: 15.0,                      # Slowest query
          queries_per_second: 9.5,                # Query throughput
          recent_queries: [...]                    # Last 10 queries for debugging
        },

        api: %{
          call_count: 50,                         # GSC API calls made
          total_rows: 5000,                       # Total rows fetched
          avg_response_time_ms: 150.0,            # Average API response time
          rate_limited_count: 0,                  # Times rate limited
          error_count: 0,                         # API errors encountered
          calls_per_second: 4.8,                  # API call throughput
          recent_calls: [...]                     # Last 10 API calls
        },

        sync: %{
          completed_count: 5,                     # Sync operations completed
          total_urls: 2500,                       # Total URLs processed
          avg_duration_ms: 500.0,                 # Average sync duration
          urls_per_second: 238.1,                 # Processing throughput
          recent_syncs: [...]                     # Last 10 sync operations
        },

        memory: %{
          process_memory: 104_857_600,            # Memory in processes (bytes)
          ets_memory: 2_097_152,                  # Memory in ETS tables
          binary_memory: 1_048_576,               # Memory in binaries
          total_memory: 209_715_200,              # Total BEAM memory
          atom_memory: 524_288,                   # Memory used by atoms
          code_memory: 10_485_760                 # Memory used by code
        },

        processes: %{
          count: 150,                             # Total process count
          max_message_queue: 0,                   # Largest mailbox
          scheduler_utilization: 0.45              # CPU utilization (0-1)
        }
      }

  ## Performance Report

      # Print comprehensive performance report
      PerformanceMonitor.print_report()

      # Output:
      # ╔══════════════════════════════════════════════════════╗
      # ║         PERFORMANCE MONITORING REPORT               ║
      # ╚══════════════════════════════════════════════════════╝
      #
      # 📊 Database Performance:
      #   • Total queries: 100
      #   • Total time: 250.00ms
      #   • Avg query time: 2.50ms
      #   • Max query time: 15.00ms
      #   • Query rate: 9.50/sec
      #
      # 🌐 GSC API Performance:
      #   • Total API calls: 50
      #   • Total rows fetched: 5000
      #   • Avg response time: 150.00ms
      #   • Rate limited: 0 times
      #   • Errors: 0
      #
      # 💾 Memory Usage:
      #   • Process memory: 100.00 MB
      #   • ETS memory: 2.00 MB
      #   • Binary refs: 1.00 MB
      #   • Total allocated: 200.00 MB

  ## Telemetry Events

  Automatically subscribes to:
  - `[:gsc_analytics, :repo, :query]` - Database queries
  - `[:gsc_analytics, :api, :request]` - API calls
  - `[:gsc_analytics, :sync, :complete]` - Sync operations
  """

  use GenServer
  require Logger

  @ets_table :performance_monitor

  # Client API

  def start do
    case GenServer.start(__MODULE__, %{}, name: __MODULE__) do
      {:ok, pid} ->
        attach_all_telemetry()
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        reset()
        {:ok, pid}

      error ->
        error
    end
  end

  def stop do
    detach_all_telemetry()

    if Process.whereis(__MODULE__) do
      GenServer.stop(__MODULE__)
    end
  end

  def reset do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :reset)
    end
  end

  def get_metrics do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :get_metrics)
    else
      %{}
    end
  end

  def print_report do
    metrics = get_metrics()

    IO.puts("\n╔══════════════════════════════════════════════════════╗")
    IO.puts("║         PERFORMANCE MONITORING REPORT               ║")
    IO.puts("╚══════════════════════════════════════════════════════╝\n")

    # Database Metrics
    if metrics[:database] do
      IO.puts("📊 Database Performance:")
      db = metrics.database
      IO.puts("  • Total queries: #{db.query_count}")
      IO.puts("  • Total time: #{Float.round(db.total_time_ms, 2)}ms")
      IO.puts("  • Avg query time: #{Float.round(db.avg_time_ms, 2)}ms")
      IO.puts("  • Max query time: #{Float.round(db.max_time_ms, 2)}ms")
      IO.puts("  • Query rate: #{Float.round(db.queries_per_second, 2)}/sec")
    end

    # API Metrics
    if metrics[:api] do
      IO.puts("\n🌐 GSC API Performance:")
      api = metrics.api
      IO.puts("  • Total API calls: #{api.call_count}")
      IO.puts("  • Total rows fetched: #{api.total_rows}")
      IO.puts("  • Avg response time: #{Float.round(api.avg_response_time_ms, 2)}ms")
      IO.puts("  • Rate limited: #{api.rate_limited_count} times")
      IO.puts("  • Errors: #{api.error_count}")
    end

    # Sync Metrics
    if metrics[:sync] do
      IO.puts("\n🔄 Sync Operations:")
      sync = metrics.sync
      IO.puts("  • Syncs completed: #{sync.completed_count}")
      IO.puts("  • URLs processed: #{sync.total_urls}")
      IO.puts("  • Avg sync time: #{Float.round(sync.avg_duration_ms, 2)}ms")
      IO.puts("  • Throughput: #{Float.round(sync.urls_per_second, 2)} URLs/sec")
    end

    # Memory Metrics
    if metrics[:memory] do
      IO.puts("\n💾 Memory Usage:")
      mem = metrics.memory
      IO.puts("  • Process memory: #{format_bytes(mem.process_memory)}")
      IO.puts("  • ETS memory: #{format_bytes(mem.ets_memory)}")
      IO.puts("  • Binary refs: #{format_bytes(mem.binary_memory)}")
      IO.puts("  • Total allocated: #{format_bytes(mem.total_memory)}")
    end

    # Process Metrics
    if metrics[:processes] do
      IO.puts("\n⚙️ Process Info:")
      proc = metrics.processes
      IO.puts("  • Process count: #{proc.count}")
      IO.puts("  • Message queue max: #{proc.max_message_queue}")
      IO.puts("  • Scheduler utilization: #{Float.round(proc.scheduler_utilization * 100, 1)}%")
    end

    IO.puts("")
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create ETS table for fast metric storage
    :ets.new(@ets_table, [:named_table, :public, :set])

    state = %{
      start_time: System.monotonic_time(:millisecond),
      database: %{
        query_count: 0,
        total_time_ms: 0.0,
        max_time_ms: 0.0,
        queries: []
      },
      api: %{
        call_count: 0,
        total_rows: 0,
        total_time_ms: 0.0,
        rate_limited_count: 0,
        error_count: 0,
        calls: []
      },
      sync: %{
        completed_count: 0,
        total_urls: 0,
        total_time_ms: 0.0,
        syncs: []
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %{
      start_time: System.monotonic_time(:millisecond),
      database: %{query_count: 0, total_time_ms: 0.0, max_time_ms: 0.0, queries: []},
      api: %{
        call_count: 0,
        total_rows: 0,
        total_time_ms: 0.0,
        rate_limited_count: 0,
        error_count: 0,
        calls: []
      },
      sync: %{completed_count: 0, total_urls: 0, total_time_ms: 0.0, syncs: []}
    }

    :ets.delete_all_objects(@ets_table)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    elapsed_seconds = (System.monotonic_time(:millisecond) - state.start_time) / 1000

    metrics = %{
      elapsed_seconds: elapsed_seconds,
      database: calculate_db_metrics(state.database, elapsed_seconds),
      api: calculate_api_metrics(state.api, elapsed_seconds),
      sync: calculate_sync_metrics(state.sync, elapsed_seconds),
      memory: get_memory_metrics(),
      processes: get_process_metrics()
    }

    {:reply, metrics, state}
  end

  @impl true
  def handle_cast({:db_query, measurements, metadata}, state) do
    duration_ms = (measurements.total_time || 0) / 1_000_000

    new_db = %{
      state.database
      | query_count: state.database.query_count + 1,
        total_time_ms: state.database.total_time_ms + duration_ms,
        max_time_ms: max(state.database.max_time_ms, duration_ms),
        queries: [{duration_ms, metadata.query} | Enum.take(state.database.queries, 99)]
    }

    {:noreply, %{state | database: new_db}}
  end

  @impl true
  def handle_cast({:api_call, measurements, metadata}, state) do
    duration_ms = measurements[:duration_ms] || 0
    rows = measurements[:rows] || 0

    new_api = %{
      state.api
      | call_count: state.api.call_count + 1,
        total_rows: state.api.total_rows + rows,
        total_time_ms: state.api.total_time_ms + duration_ms,
        rate_limited_count:
          state.api.rate_limited_count + if(metadata[:rate_limited], do: 1, else: 0),
        error_count: state.api.error_count + if(metadata[:error], do: 1, else: 0),
        calls: [{duration_ms, rows, metadata} | Enum.take(state.api.calls, 99)]
    }

    {:noreply, %{state | api: new_api}}
  end

  @impl true
  def handle_cast({:sync_complete, measurements, metadata}, state) do
    duration_ms = measurements[:duration_ms] || 0
    urls = measurements[:total_urls] || 0

    new_sync = %{
      state.sync
      | completed_count: state.sync.completed_count + 1,
        total_urls: state.sync.total_urls + urls,
        total_time_ms: state.sync.total_time_ms + duration_ms,
        syncs: [{duration_ms, urls, metadata} | Enum.take(state.sync.syncs, 49)]
    }

    {:noreply, %{state | sync: new_sync}}
  end

  # Telemetry handlers

  defp attach_all_telemetry do
    # Database telemetry
    :telemetry.attach(
      "perf-monitor-db",
      [:gsc_analytics, :repo, :query],
      &handle_db_telemetry/4,
      nil
    )

    # API telemetry
    :telemetry.attach(
      "perf-monitor-api",
      [:gsc_analytics, :api, :request],
      &handle_api_telemetry/4,
      nil
    )

    # Sync telemetry
    :telemetry.attach(
      "perf-monitor-sync",
      [:gsc_analytics, :sync, :complete],
      &handle_sync_telemetry/4,
      nil
    )
  end

  defp detach_all_telemetry do
    :telemetry.detach("perf-monitor-db")
    :telemetry.detach("perf-monitor-api")
    :telemetry.detach("perf-monitor-sync")
  end

  def handle_db_telemetry(_event, measurements, metadata, _config) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:db_query, measurements, metadata})
    end
  end

  def handle_api_telemetry(_event, measurements, metadata, _config) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:api_call, measurements, metadata})
    end
  end

  def handle_sync_telemetry(_event, measurements, metadata, _config) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:sync_complete, measurements, metadata})
    end
  end

  # Metric calculations

  defp calculate_db_metrics(db, elapsed_seconds) do
    %{
      query_count: db.query_count,
      total_time_ms: db.total_time_ms,
      avg_time_ms: if(db.query_count > 0, do: db.total_time_ms / db.query_count, else: 0.0),
      max_time_ms: db.max_time_ms,
      queries_per_second:
        if(elapsed_seconds > 0, do: db.query_count / elapsed_seconds, else: 0.0),
      recent_queries: Enum.take(db.queries, 10)
    }
  end

  defp calculate_api_metrics(api, elapsed_seconds) do
    %{
      call_count: api.call_count,
      total_rows: api.total_rows,
      avg_response_time_ms:
        if(api.call_count > 0, do: api.total_time_ms / api.call_count, else: 0.0),
      rate_limited_count: api.rate_limited_count,
      error_count: api.error_count,
      calls_per_second: if(elapsed_seconds > 0, do: api.call_count / elapsed_seconds, else: 0.0),
      recent_calls: Enum.take(api.calls, 10)
    }
  end

  defp calculate_sync_metrics(sync, elapsed_seconds) do
    %{
      completed_count: sync.completed_count,
      total_urls: sync.total_urls,
      avg_duration_ms:
        if(sync.completed_count > 0, do: sync.total_time_ms / sync.completed_count, else: 0.0),
      urls_per_second: if(elapsed_seconds > 0, do: sync.total_urls / elapsed_seconds, else: 0.0),
      recent_syncs: Enum.take(sync.syncs, 10)
    }
  end

  defp get_memory_metrics do
    memory_data = :erlang.memory()

    %{
      process_memory: memory_data[:processes],
      ets_memory: memory_data[:ets],
      binary_memory: memory_data[:binary],
      total_memory: memory_data[:total],
      atom_memory: memory_data[:atom],
      code_memory: memory_data[:code]
    }
  end

  defp get_process_metrics do
    process_count = :erlang.system_info(:process_count)

    # Get scheduler utilization - returns a list of tuples
    scheduler_util =
      case :scheduler.utilization(1) do
        [_ | _] = results ->
          # Find the :total tuple in the results list
          case Enum.find(results, fn
                 {:total, _, _} -> true
                 _ -> false
               end) do
            {:total, util, _} -> util
            _ -> 0.0
          end

        _ ->
          0.0
      end

    # Get max message queue length
    max_queue =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> len
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    %{
      count: process_count,
      max_message_queue: max_queue,
      scheduler_utilization: scheduler_util
    }
  rescue
    _ ->
      # Fallback if scheduler info not available
      %{
        count: :erlang.system_info(:process_count),
        max_message_queue: 0,
        scheduler_utilization: 0.0
      }
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "N/A"
end
