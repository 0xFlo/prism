defmodule GscAnalytics.DataSources.GSC.Support.QueryBatchProducer do
  @moduledoc """
  Broadway producer that pulls pagination batches from the QueryCoordinator.
  """

  use GenStage
  @behaviour Broadway.Producer

  alias Broadway.NoopAcknowledger
  alias GscAnalytics.DataSources.GSC.Support.QueryCoordinator

  def init(opts) do
    coordinator = Keyword.fetch!(opts, :coordinator)
    batch_size = Keyword.fetch!(opts, :batch_size)

    state = %{
      coordinator: coordinator,
      batch_size: batch_size,
      retry_sleep: Keyword.get(opts, :retry_sleep_ms, 50),
      owner: Keyword.fetch!(opts, :owner),
      stopped?: false
    }

    {:producer, state}
  end

  def handle_demand(demand, state) when demand > 0, do: dispatch_batches(demand, state, [])
  def handle_demand(_demand, state), do: {:noreply, [], state}

  defp dispatch_batches(0, state, acc), do: {:noreply, Enum.reverse(acc), state}

  defp dispatch_batches(_demand, %{stopped?: true} = state, acc) do
    {:noreply, Enum.reverse(acc), state}
  end

  defp dispatch_batches(demand, state, acc) do
    case QueryCoordinator.take_batch(state.coordinator, state.batch_size) do
      {:ok, batch} ->
        message = %Broadway.Message{data: batch, acknowledger: NoopAcknowledger.init()}
        dispatch_batches(demand - 1, state, [message | acc])

      {:backpressure, _reason} ->
        Process.sleep(state.retry_sleep)
        {:noreply, Enum.reverse(acc), state}

      :pending ->
        Process.sleep(state.retry_sleep)
        {:noreply, Enum.reverse(acc), state}

      :no_more_work ->
        send(state.owner, {:query_pipeline_complete, :ok})
        {:noreply, Enum.reverse(acc), %{state | stopped?: true}}

      {:halted, reason} ->
        send(state.owner, {:query_pipeline_complete, {:halt, reason}})
        {:noreply, Enum.reverse(acc), %{state | stopped?: true}}
    end
  end
end
