defmodule GscAnalytics.Broadway.DirectProducer do
  @moduledoc """
  Simple in-memory producer that allows pushing messages directly into Broadway.
  """

  use GenStage
  @behaviour Broadway.Producer

  defstruct queue: :queue.new(), demand: 0

  @type state :: %__MODULE__{queue: :queue.queue(), demand: non_neg_integer()}

  @impl true
  def init(_opts) do
    {:producer, %__MODULE__{}}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    dispatch(%{state | demand: demand + incoming_demand})
  end

  @impl true
  def handle_cast({:push, messages}, %{queue: queue} = state) when is_list(messages) do
    new_queue = Enum.reduce(messages, queue, &:queue.in/2)
    dispatch(%{state | queue: new_queue})
  end

  @doc """
  Pushes messages to the producer.
  """
  def push(pid, messages) when is_list(messages) do
    cond do
      is_pid(pid) and Process.alive?(pid) ->
        GenServer.cast(pid, {:push, messages})
        :ok

      true ->
        {:error, :producer_down}
    end
  end

  defp dispatch(%{queue: queue, demand: demand} = state) do
    {events, queue} = take_events(queue, demand, [])
    sent = length(events)
    {:noreply, Enum.reverse(events), %{state | queue: queue, demand: max(demand - sent, 0)}}
  end

  defp take_events(queue, demand, acc) do
    cond do
      demand <= 0 ->
        {acc, queue}

      true ->
        case :queue.out(queue) do
          {:empty, queue} ->
            {acc, queue}

          {{:value, item}, queue} ->
            take_events(queue, demand - 1, [item | acc])
        end
    end
  end
end
