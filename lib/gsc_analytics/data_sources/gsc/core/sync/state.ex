defmodule GscAnalytics.DataSources.GSC.Core.Sync.State do
  @moduledoc """
  Sync state management with explicit structure and transitions.

  Replaces the ad-hoc state map with a typed struct and provides
  Agent-based metrics storage for cross-process communication.

  ## Examples

      dates = [~D[2024-01-01], ~D[2024-01-02]]
      state = State.new(123, 1, "sc-domain:example.com", dates, force?: false)
      step = State.get_step(state, ~D[2024-01-01])
      State.store_query_count(state, ~D[2024-01-01], 42)
      counts = State.take_query_counts(state)
      :ok = State.cleanup(state)
  """

  alias __MODULE__
  alias MapSet

  defstruct [
    :job_id,
    :account_id,
    :site_url,
    :dates,
    :date_steps,
    :metrics_agent,
    results: %{},
    query_failures: MapSet.new(),
    empty_streak: 0,
    has_seen_data?: false,
    total_urls: 0,
    total_queries: 0,
    total_query_sub_requests: 0,
    total_query_http_batches: 0,
    api_calls: 0,
    halted?: false,
    halt_reason: nil,
    halt_error_message: nil,
    halted_on_date: nil,
    current_step: 0,
    total_steps: 0,
    opts: []
  ]

  @doc "Create new sync state with initialized Agent"
  def new(job_id, account_id, site_url, dates, opts) do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    date_steps =
      dates
      |> Enum.with_index(1)
      |> Map.new()

    %State{
      job_id: job_id,
      account_id: account_id,
      site_url: site_url,
      dates: dates,
      date_steps: date_steps,
      metrics_agent: agent,
      current_step: 0,
      total_steps: length(dates),
      opts: opts
    }
  end

  @doc "Get step number for a date"
  def get_step(%State{date_steps: steps}, date) do
    Map.fetch!(steps, date)
  end

  @doc "Store query count in Agent"
  def store_query_count(%State{metrics_agent: agent}, date, count)
      when is_integer(count) and count >= 0 do
    Agent.update(agent, &Map.put(&1, date, count))
  end

  def store_query_count(_, _, _), do: :ok

  @doc "Retrieve and clear query counts from Agent"
  def take_query_counts(%State{metrics_agent: agent}) do
    Agent.get_and_update(agent, fn metrics -> {metrics, %{}} end)
  end

  @doc "Clean up Agent when sync completes"
  def cleanup(%State{metrics_agent: agent}) do
    Agent.stop(agent, :normal)
  end

  @doc "Add query failure date"
  def add_query_failure(%State{query_failures: failures} = state, date) do
    %{state | query_failures: MapSet.put(failures, date)}
  end

  @doc "Add multiple query failure dates"
  def add_query_failures(%State{query_failures: failures} = state, dates) do
    %{state | query_failures: MapSet.union(failures, MapSet.new(dates))}
  end
end
