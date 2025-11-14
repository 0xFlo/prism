# GenServer Coordination Patterns for Concurrent Batch Processing

## Overview

This guide covers best practices for implementing GenServer-based coordination for concurrent batch processing in Elixir/OTP, with specific focus on patterns relevant to the GSC Analytics sync optimization sprint.

## Official Documentation

- **GenServer**: https://hexdocs.pm/elixir/GenServer.html
- **GenServer Guide**: https://hexdocs.pm/elixir/genservers.html
- **Task.Supervisor**: https://hexdocs.pm/elixir/Task.Supervisor.html
- **DynamicSupervisor**: https://hexdocs.pm/elixir/DynamicSupervisor.html
- **GenStage**: https://hexdocs.pm/gen_stage/GenStage.html
- **Broadway**: https://hexdocs.pm/broadway/Broadway.html

---

## Core Patterns

### 1. GenServer as Dispatcher Pattern

GenServers handle one message at a time, making them excellent coordinators but potential bottlenecks if they do heavy computation.

**Best Practice**: Coordinator GenServers should only manage state and delegate work, not perform heavy computation.

```elixir
defmodule QueryCoordinator do
  use GenServer

  # Client API - delegates work, doesn't block
  def take_batch(coordinator, worker_id) do
    GenServer.call(coordinator, {:take_batch, worker_id})
  end

  # Server callbacks - fast state updates only
  def handle_call({:take_batch, worker_id}, _from, state) do
    case :queue.out(state.batch_queue) do
      {{:value, batch}, new_queue} ->
        # Update state, track in-flight work
        new_state = track_batch(state, worker_id, batch)
        {:reply, {:ok, batch}, %{state | batch_queue: new_queue}}

      {:empty, _} ->
        {:reply, :no_batches, state}
    end
  end

  # Heavy work delegated to workers
  defp track_batch(state, worker_id, batch) do
    # Fast ETS write, not blocking
    :ets.insert(state.in_flight_table, {batch.id, worker_id, System.monotonic_time()})
    update_in(state.in_flight_count, &(&1 + 1))
  end
end
```

**Key Points**:
- Client functions handle serialization (`GenServer.call`)
- Server callbacks only update state
- Heavy computation delegated to Task workers
- Use ETS for shared state that workers can read without messaging

---

### 2. Multi-Instance Pattern for Scalability

If a single GenServer becomes a bottleneck, start multiple instances and distribute load.

```elixir
defmodule CoordinatorPool do
  @pool_size 4

  def start_link do
    children = for i <- 1..@pool_size do
      Supervisor.child_spec(
        {QueryCoordinator, name: via_tuple(i)},
        id: {QueryCoordinator, i}
      )
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  # Hash-based routing
  def take_batch(property_url) do
    coordinator_id = :erlang.phash2(property_url, @pool_size) + 1
    QueryCoordinator.take_batch(via_tuple(coordinator_id), property_url)
  end

  defp via_tuple(id), do: {:via, Registry, {CoordinatorRegistry, id}}
end
```

**When to Use**:
- Single coordinator's mailbox depth consistently > 500 messages
- Latency spikes due to queue processing
- Multiple independent workloads (e.g., per-property sync)

---

## Backpressure and Queue Management

### The Problem

Elixir processes do not backpressure by default. GenServer mailboxes can grow unbounded, leading to:
- Out-of-memory errors
- Scheduler starvation
- Unpredictable latency

### Solution 1: Queue Limits with Rejection

```elixir
defmodule BackpressureCoordinator do
  use GenServer

  @max_queue_size 1000
  @max_in_flight 10

  def enqueue_batch(coordinator, batch) do
    GenServer.call(coordinator, {:enqueue, batch})
  end

  def handle_call({:enqueue, batch}, _from, state) do
    cond do
      :queue.len(state.batch_queue) >= @max_queue_size ->
        {:reply, {:error, :queue_full}, state}

      state.in_flight_count >= @max_in_flight ->
        {:reply, {:error, :backpressure}, state}

      true ->
        new_queue = :queue.in(batch, state.batch_queue)
        {:reply, :ok, %{state | batch_queue: new_queue}}
    end
  end
end
```

**Benefits**:
- Fail fast instead of queuing indefinitely
- Predictable memory usage
- Clear signal to upstream producers

---

### Solution 2: Monitor Mailbox Size

```elixir
defmodule MailboxMonitor do
  @alert_threshold 500
  @critical_threshold 800

  def check_health(coordinator_pid) do
    {:message_queue_len, len} = Process.info(coordinator_pid, :message_queue_len)

    cond do
      len >= @critical_threshold ->
        Logger.error("Coordinator mailbox critical: #{len} messages")
        {:critical, len}

      len >= @alert_threshold ->
        Logger.warn("Coordinator mailbox high: #{len} messages")
        {:warn, len}

      true ->
        {:ok, len}
    end
  end
end
```

**Integration with Telemetry**:

```elixir
defp periodic_measurements do
  [
    {__MODULE__, :measure_coordinator_mailbox, []}
  ]
end

def measure_coordinator_mailbox do
  {:message_queue_len, len} = Process.info(QueryCoordinator, :message_queue_len)

  :telemetry.execute(
    [:gsc_analytics, :coordinator, :mailbox],
    %{size: len},
    %{}
  )
end
```

---

### Solution 3: GenStage for Pull-Based Backpressure

For production pipelines requiring strict backpressure, use GenStage:

```elixir
defmodule Producer do
  use GenStage

  def start_link(initial) do
    GenStage.start_link(__MODULE__, initial)
  end

  def init(batches) do
    {:producer, {:queue.from_list(batches), 0}}
  end

  def handle_demand(demand, {queue, pending_demand}) do
    {batches, new_queue} = take_batches(queue, demand + pending_demand)

    case batches do
      [] ->
        {:noreply, [], {new_queue, demand + pending_demand}}

      batches ->
        {:noreply, batches, {new_queue, 0}}
    end
  end
end

defmodule Consumer do
  use GenStage

  def start_link do
    GenStage.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {:consumer, :ok}
  end

  def handle_events(batches, _from, state) do
    # Process batches
    Enum.each(batches, &process_batch/1)
    {:noreply, [], state}
  end
end
```

**When to Use GenStage**:
- Complex multi-stage pipelines
- Strict backpressure requirements
- Need for automatic demand management

**When to Use Simple GenServer**:
- Single coordinator + worker pool
- Can tolerate occasional rejection
- Simpler implementation requirements

---

## ETS-Backed State Recovery

### The Challenge

GenServers crash and restart. How do we preserve critical state?

### Pattern: ETS Backup with Continuation

```elixir
defmodule ResilientCoordinator do
  use GenServer

  def init(opts) do
    ets_table = :ets.new(:coordinator_state, [
      :set,
      :public,
      :named_table,
      read_concurrency: true
    ])

    # Restore from ETS if available
    state = case :ets.lookup(:coordinator_state, :state) do
      [{:state, restored_state}] ->
        Logger.info("Restored coordinator state from ETS")
        restored_state

      [] ->
        Logger.info("Starting coordinator with fresh state")
        initial_state()
    end

    {:ok, Map.put(state, :ets_table, ets_table)}
  end

  # Persist state changes to ETS
  defp persist_state(state) do
    :ets.insert(:coordinator_state, {:state, state})
    state
  end

  def handle_call({:enqueue, batch}, _from, state) do
    new_state =
      state
      |> enqueue_batch_to_queue(batch)
      |> persist_state()  # Persist after each state change

    {:reply, :ok, new_state}
  end
end
```

**Important Considerations**:

1. **Don't blindly restore**: May preserve bugs that caused crash
2. **Selective restoration**: Only restore critical data (e.g., in-flight batches)
3. **Event sourcing alternative**: Store events, rebuild state on restart

### Pattern: In-Flight Tracking with ETS

For Phase 4 QueryCoordinator, track in-flight batches in ETS for crash recovery:

```elixir
defmodule InFlightTracker do
  @table_name :in_flight_batches

  def init do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  def track_batch(batch_id, worker_pid, metadata) do
    :ets.insert(@table_name, {batch_id, worker_pid, metadata, System.monotonic_time()})
  end

  def complete_batch(batch_id) do
    :ets.delete(@table_name, batch_id)
  end

  def recover_abandoned_batches do
    # Find batches with dead workers
    :ets.select(@table_name, [
      {{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", :"$2", :"$3", :"$4"}}]}
    ])
    |> Enum.filter(fn {_id, worker_pid, _meta, _time} ->
      not Process.alive?(worker_pid)
    end)
    |> Enum.map(fn {batch_id, _pid, metadata, _time} ->
      {batch_id, metadata}
    end)
  end
end
```

**Benefits**:
- Survives coordinator crashes
- Workers can check their own status
- Fast concurrent reads/writes

---

## Task Supervision Patterns

### Basic Task.Supervisor Usage

```elixir
# In application.ex
children = [
  {Task.Supervisor, name: GscAnalytics.TaskSupervisor}
]

# In coordinator
def spawn_worker(batch) do
  Task.Supervisor.async_nolink(
    GscAnalytics.TaskSupervisor,
    fn -> process_batch(batch) end
  )
end
```

**Key Options**:
- `async`: Links task to caller (crash propagates)
- `async_nolink`: Isolates failures (recommended for workers)

### DynamicSupervisor for Long-Running Workers

For workers that need to survive coordinator crashes:

```elixir
defmodule WorkerPool do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker(worker_id, opts) do
    spec = {BatchWorker, [worker_id: worker_id] ++ opts}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end

defmodule BatchWorker do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: via_tuple(opts[:worker_id]))
  end

  def init(opts) do
    # Register with coordinator
    QueryCoordinator.register_worker(self(), opts[:worker_id])

    # Start work loop
    {:ok, %{worker_id: opts[:worker_id]}, {:continue, :fetch_batch}}
  end

  def handle_continue(:fetch_batch, state) do
    case QueryCoordinator.take_batch(state.worker_id) do
      {:ok, batch} ->
        process_batch(batch)
        {:noreply, state, {:continue, :fetch_batch}}

      :no_batches ->
        Process.send_after(self(), :retry_fetch, 1000)
        {:noreply, state}
    end
  end

  defp via_tuple(worker_id) do
    {:via, Registry, {WorkerRegistry, worker_id}}
  end
end
```

---

## Broadway for Production Pipelines

For production-grade concurrent processing with built-in backpressure:

```elixir
defmodule GSCBatchPipeline do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "gsc_batches"},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 10,
          max_demand: 5
        ]
      ],
      batchers: [
        persistence: [
          batch_size: 100,
          batch_timeout: 1000,
          concurrency: 5
        ]
      ]
    )
  end

  def handle_message(_processor, message, _context) do
    # Process individual batch
    result = fetch_and_process_batch(message.data)

    message
    |> Message.update_data(fn _ -> result end)
    |> Message.put_batcher(:persistence)
  end

  def handle_batch(:persistence, messages, _batch_info, _context) do
    # Batch persist to database
    data = Enum.map(messages, & &1.data)
    Persistence.insert_all(data)

    messages
  end
end
```

**When to Use Broadway**:
- Production data pipelines
- Queue-based processing (SQS, Kafka, RabbitMQ)
- Need automatic retries and acknowledgements
- Built-in backpressure required

---

## Recommended Architecture for Phase 4

```
┌─────────────────────────────────────────┐
│   QueryCoordinator (GenServer)          │
│   - Manages batch queue                 │
│   - Tracks in-flight via ETS            │
│   - Enforces backpressure limits        │
│   - Single instance per property        │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│   Task.Supervisor                       │
│   - Supervises worker tasks             │
│   - Restart strategy: transient         │
└─────────────────┬───────────────────────┘
                  │
                  ↓
┌─────────────────────────────────────────┐
│   Concurrent Workers (Task.async)       │
│   - Fetch batches from coordinator      │
│   - Check rate limits before HTTP       │
│   - Submit results back                 │
│   - max_concurrency: 3 (configurable)   │
└─────────────────────────────────────────┘
```

**Key Design Decisions**:
1. GenServer coordinator (not GenStage) - simpler for single-stage processing
2. Task.Supervisor for worker management - proven pattern
3. ETS for crash recovery - fast, concurrent access
4. Backpressure via queue limits - explicit and controllable

---

## Testing GenServer Coordinators

```elixir
defmodule QueryCoordinatorTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, coordinator} = QueryCoordinator.start_link([])
    %{coordinator: coordinator}
  end

  test "enforces max queue size", %{coordinator: coordinator} do
    # Fill queue to limit
    for i <- 1..1000 do
      assert :ok = QueryCoordinator.enqueue_batch(coordinator, %{id: i})
    end

    # Next enqueue should fail
    assert {:error, :queue_full} = QueryCoordinator.enqueue_batch(coordinator, %{id: 1001})
  end

  test "tracks in-flight batches", %{coordinator: coordinator} do
    QueryCoordinator.enqueue_batch(coordinator, %{id: 1})

    {:ok, batch} = QueryCoordinator.take_batch(coordinator, :worker_1)

    # Verify ETS tracking
    assert [{1, :worker_1, _timestamp}] = :ets.lookup(:in_flight_batches, 1)
  end

  test "recovers abandoned batches on worker crash", %{coordinator: coordinator} do
    QueryCoordinator.enqueue_batch(coordinator, %{id: 1})

    # Spawn worker that crashes
    worker_pid = spawn(fn ->
      {:ok, _batch} = QueryCoordinator.take_batch(coordinator, :worker_1)
      raise "simulated crash"
    end)

    # Wait for crash
    ref = Process.monitor(worker_pid)
    assert_receive {:DOWN, ^ref, :process, ^worker_pid, _reason}

    # Coordinator should detect and re-enqueue
    abandoned = QueryCoordinator.recover_abandoned_batches(coordinator)
    assert length(abandoned) == 1
  end
end
```

---

## Key Takeaways

1. **GenServers coordinate, workers compute** - Keep GenServer callbacks fast
2. **Multi-instance for scale** - Single GenServer can bottleneck at high concurrency
3. **Implement backpressure** - Queue limits + mailbox monitoring prevent OOM
4. **ETS for crash recovery** - Fast, concurrent, survives coordinator crashes
5. **Task.Supervisor for workers** - Standard pattern for concurrent tasks
6. **Broadway for complex pipelines** - When you need more than basic coordination

---

## Resources

- **Avoiding GenServer Bottlenecks**: https://www.cogini.com/blog/avoiding-genserver-bottlenecks/
- **Building Concurrent Task Management**: https://medium.com/@jonnyeberhardt7/building-a-concurrent-and-parallel-task-management-system-with-elixirs-otp-85413faf5d4e
- **GenServer State Recovery**: https://www.bounga.org/elixir/2020/02/29/genserver-supervision-tree-and-state-recovery-after-crash/
- **OTP Design Principles**: https://www.erlang.org/doc/design_principles/users_guide.html
