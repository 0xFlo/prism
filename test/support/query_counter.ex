defmodule GscAnalytics.Test.QueryCounter do
  @moduledoc """
  Counts and analyzes database queries during tests.
  Helps identify N+1 queries and performance regressions.

  ## Features

  - **Query Counting**: Tracks total number of database queries
  - **Performance Metrics**: Measures total and average query time
  - **N+1 Detection**: Automatically identifies N+1 query patterns
  - **Slow Query Detection**: Flags queries exceeding threshold (default 100ms)
  - **Duplicate Detection**: Finds exact duplicate queries
  - **Table Analysis**: Groups queries by table for insight
  - **Operation Analysis**: Groups by SELECT/INSERT/UPDATE/DELETE

  ## Basic Usage

      setup do
        QueryCounter.start()
        on_exit(fn -> QueryCounter.stop() end)
        :ok
      end

      test "my test" do
        # ... run code ...

        analysis = QueryCounter.analyze()
        assert analysis.total_count < 10
        assert analysis.n_plus_one == []
      end

  ## Advanced Usage

      test "compare two implementations" do
        # Test implementation A
        QueryCounter.reset()
        implementation_a()
        metrics_a = QueryCounter.analyze()

        # Test implementation B
        QueryCounter.reset()
        implementation_b()
        metrics_b = QueryCounter.analyze()

        # Compare
        assert metrics_b.total_count < metrics_a.total_count
        improvement = metrics_a.total_count - metrics_b.total_count
        IO.puts("Improvement: \#{improvement} fewer queries")
      end

  ## Analysis Output Structure

      %{
        total_count: 42,                         # Total queries executed
        total_time_ms: 125.5,                   # Total time in database
        by_table: %{                            # Queries grouped by table
          users: %{count: 10, total_time_ms: 25.0},
          posts: %{count: 32, total_time_ms: 100.5}
        },
        by_operation: %{                        # Queries grouped by operation
          select: %{count: 30, total_time_ms: 75.0},
          insert: %{count: 12, total_time_ms: 50.5}
        },
        slow_queries: [                         # Queries > 100ms
          %{duration_ms: 150.0, query: "SELECT ..."}
        ],
        n_plus_one: [                           # Detected N+1 patterns
          %{
            pattern: "SELECT ... WHERE user_id = ?",
            count: 50,
            total_time_ms: 200.0,
            avg_time_ms: 4.0
          }
        ],
        duplicate_queries: [                    # Exact duplicates
          %{
            query: "SELECT * FROM users WHERE id = 1",
            count: 5,
            total_time_ms: 10.0
          }
        ]
      }

  ## Performance Assertions

      # Assert on specific metrics
      assert analysis.total_count < 20, "Too many queries: \#{analysis.total_count}"
      assert analysis.total_time_ms < 500, "Queries too slow: \#{analysis.total_time_ms}ms"
      assert analysis.n_plus_one == [], "N+1 queries detected: \#{inspect(analysis.n_plus_one)}"

      # Assert on specific tables
      assert analysis.by_table.users.count < 5, "Too many user queries"

      # Print detailed report for debugging
      QueryCounter.print_analysis()
  """

  use GenServer
  require Logger

  # Client API

  def start do
    case GenServer.start(__MODULE__, %{}, name: __MODULE__) do
      {:ok, pid} ->
        attach_telemetry()
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        reset()
        {:ok, pid}

      error ->
        error
    end
  end

  def stop do
    detach_telemetry()

    if Process.whereis(__MODULE__) do
      GenServer.stop(__MODULE__)
    end
  end

  def reset do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :reset)
    end
  end

  def count do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :count)
    else
      0
    end
  end

  def queries do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :queries)
    else
      []
    end
  end

  def analyze do
    queries = queries()

    %{
      total_count: length(queries),
      total_time_ms: calculate_total_time(queries),
      by_table: group_by_table(queries),
      by_operation: group_by_operation(queries),
      slow_queries: find_slow_queries(queries, 100),
      n_plus_one: detect_n_plus_one(queries),
      duplicate_queries: find_duplicate_queries(queries)
    }
  end

  def print_analysis do
    analysis = analyze()

    IO.puts("\n╔══════════════════════════════════════════════════════╗")
    IO.puts("║           QUERY ANALYSIS REPORT                     ║")
    IO.puts("╚══════════════════════════════════════════════════════╝\n")

    IO.puts("📊 Summary:")
    IO.puts("  • Total queries: #{analysis.total_count}")
    IO.puts("  • Total time: #{Float.round(analysis.total_time_ms, 2)}ms")

    IO.puts(
      "  • Avg per query: #{Float.round(analysis.total_time_ms / max(analysis.total_count, 1), 2)}ms"
    )

    if analysis.n_plus_one != [] do
      IO.puts("\n⚠️  N+1 Queries Detected:")

      for problem <- analysis.n_plus_one do
        IO.puts("  • #{problem.pattern} (#{problem.count} times)")
        IO.puts("    Total time wasted: #{Float.round(problem.total_time_ms, 2)}ms")
      end
    end

    if analysis.slow_queries != [] do
      IO.puts("\n🐌 Slow Queries (>100ms):")

      for query <- Enum.take(analysis.slow_queries, 3) do
        IO.puts(
          "  • #{Float.round(query.duration_ms, 2)}ms: #{String.slice(query.query, 0, 60)}..."
        )
      end
    end

    IO.puts("\n📋 By Operation:")

    for {op, stats} <- analysis.by_operation do
      IO.puts("  • #{op}: #{stats.count} queries, #{Float.round(stats.total_time_ms, 2)}ms")
    end

    IO.puts("\n📁 By Table:")

    for {table, stats} <- analysis.by_table do
      IO.puts("  • #{table}: #{stats.count} queries, #{Float.round(stats.total_time_ms, 2)}ms")
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, %{queries: [], count: 0, start_time: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok,
     %{state | queries: [], count: 0, start_time: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, state.count, state}
  end

  @impl true
  def handle_call(:queries, _from, state) do
    {:reply, state.queries, state}
  end

  @impl true
  def handle_cast({:query, measurements, metadata}, state) do
    query_info = %{
      query: metadata.query || "",
      source: metadata.source || "",
      duration_ms: Map.get(measurements, :total_time, 0) / 1_000_000,
      decode_time_ms: Map.get(measurements, :decode_time, 0) / 1_000_000,
      queue_time_ms: Map.get(measurements, :queue_time, 0) / 1_000_000,
      timestamp: System.monotonic_time(:millisecond) - state.start_time
    }

    {:noreply,
     %{
       state
       | queries: [query_info | state.queries],
         count: state.count + 1
     }}
  end

  # Telemetry handling

  defp attach_telemetry do
    :telemetry.attach(
      "query-counter",
      [:gsc_analytics, :repo, :query],
      &handle_telemetry_event/4,
      nil
    )
  end

  defp detach_telemetry do
    :telemetry.detach("query-counter")
  end

  def handle_telemetry_event(_event_name, measurements, metadata, _config) do
    if Process.whereis(__MODULE__) do
      GenServer.cast(__MODULE__, {:query, measurements, metadata})
    end
  end

  # Analysis functions

  defp calculate_total_time(queries) do
    queries
    |> Enum.map(& &1.duration_ms)
    |> Enum.sum()
  end

  defp group_by_table(queries) do
    queries
    |> Enum.group_by(&extract_table_name/1)
    |> Enum.reject(fn {table, _} -> table == :unknown end)
    |> Enum.map(fn {table, table_queries} ->
      {table,
       %{
         count: length(table_queries),
         total_time_ms: calculate_total_time(table_queries)
       }}
    end)
    |> Enum.into(%{})
  end

  defp group_by_operation(queries) do
    queries
    |> Enum.group_by(&extract_operation/1)
    |> Enum.map(fn {op, op_queries} ->
      {op,
       %{
         count: length(op_queries),
         total_time_ms: calculate_total_time(op_queries)
       }}
    end)
    |> Enum.into(%{})
  end

  defp extract_table_name(%{source: source}) when is_binary(source) and source != "" do
    String.to_atom(source)
  end

  defp extract_table_name(%{query: query}) do
    cond do
      query =~ ~r/FROM "?(\w+)"?/i ->
        [_, table] = Regex.run(~r/FROM "?(\w+)"?/i, query)
        String.to_atom(table)

      query =~ ~r/INSERT INTO "?(\w+)"?/i ->
        [_, table] = Regex.run(~r/INSERT INTO "?(\w+)"?/i, query)
        String.to_atom(table)

      query =~ ~r/UPDATE "?(\w+)"?/i ->
        [_, table] = Regex.run(~r/UPDATE "?(\w+)"?/i, query)
        String.to_atom(table)

      query =~ ~r/DELETE FROM "?(\w+)"?/i ->
        [_, table] = Regex.run(~r/DELETE FROM "?(\w+)"?/i, query)
        String.to_atom(table)

      true ->
        :unknown
    end
  end

  defp extract_operation(%{query: query}) do
    cond do
      String.starts_with?(query, "SELECT") -> :select
      String.starts_with?(query, "INSERT") -> :insert
      String.starts_with?(query, "UPDATE") -> :update
      String.starts_with?(query, "DELETE") -> :delete
      String.starts_with?(query, "begin") -> :transaction
      String.starts_with?(query, "commit") -> :transaction
      String.starts_with?(query, "rollback") -> :transaction
      true -> :other
    end
  end

  defp find_slow_queries(queries, threshold_ms) do
    queries
    |> Enum.filter(&(&1.duration_ms > threshold_ms))
    |> Enum.sort_by(& &1.duration_ms, :desc)
  end

  defp detect_n_plus_one(queries) do
    queries
    |> Enum.filter(&(&1.query =~ ~r/SELECT.*WHERE/i))
    |> Enum.group_by(&normalize_query/1)
    |> Enum.filter(fn {_pattern, group} -> length(group) > 5 end)
    |> Enum.map(fn {pattern, group} ->
      %{
        pattern: String.slice(pattern, 0, 100),
        count: length(group),
        total_time_ms: calculate_total_time(group),
        avg_time_ms: calculate_total_time(group) / length(group)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp find_duplicate_queries(queries) do
    queries
    |> Enum.group_by(& &1.query)
    |> Enum.filter(fn {_query, group} -> length(group) > 1 end)
    |> Enum.map(fn {query, group} ->
      %{
        query: String.slice(query, 0, 100),
        count: length(group),
        total_time_ms: calculate_total_time(group)
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp normalize_query(%{query: query}) do
    query
    # Replace numbered params with ?
    |> String.replace(~r/\$\d+/, "?")
    # Replace numbers with N
    |> String.replace(~r/\d+/, "N")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
  end
end
