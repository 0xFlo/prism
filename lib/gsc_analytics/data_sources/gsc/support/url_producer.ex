defmodule GscAnalytics.DataSources.GSC.Support.URLProducer do
  @moduledoc false

  use GenStage
  @behaviour Broadway.Producer

  alias Broadway.NoopAcknowledger

  def init(opts) do
    dates = Keyword.fetch!(opts, :dates)
    owner = Keyword.fetch!(opts, :owner)

    state = %{
      queue: :queue.from_list(dates),
      owner: owner,
      complete_sent?: false
    }

    {:producer, state}
  end

  def handle_demand(demand, state) when demand > 0 do
    dispatch(demand, state, [])
  end

  def handle_demand(_demand, state), do: {:noreply, [], state}

  defp dispatch(0, state, acc), do: {:noreply, Enum.reverse(acc), state}

  defp dispatch(_demand, %{complete_sent?: true} = state, acc) do
    {:noreply, Enum.reverse(acc), state}
  end

  defp dispatch(demand, state, acc) do
    case :queue.out(state.queue) do
      {:empty, _queue} ->
        unless state.complete_sent? do
          send(state.owner, {:url_pipeline_complete, :ok})
        end

        {:noreply, Enum.reverse(acc), %{state | complete_sent?: true}}

      {{:value, date}, queue} ->
        message = %Broadway.Message{data: date, acknowledger: NoopAcknowledger.init()}
        dispatch(demand - 1, %{state | queue: queue}, [message | acc])
    end
  end
end
