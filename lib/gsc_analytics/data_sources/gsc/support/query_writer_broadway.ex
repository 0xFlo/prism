defmodule GscAnalytics.DataSources.GSC.Support.QueryWriterBroadway do
  @moduledoc """
  Broadway pipeline responsible for executing query writer callbacks.

  Replaces the ad-hoc Task.Supervisor based pool with demand-driven
  processing so pagination can backpressure automatically when DB writes
  fall behind.
  """

  use Broadway

  require Logger

  alias Broadway.{Message, NoopAcknowledger}
  alias GscAnalytics.Broadway.DirectProducer
  alias GscAnalytics.DataSources.GSC.Core.Config

  @type enqueue_result :: :ok | {:error, term()}

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    stages = Keyword.get(opts, :stages, Config.query_writer_max_concurrency())

    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [module: {DirectProducer, []}],
      processors: [
        writers: [concurrency: max(stages, 1)]
      ]
    )
  end

  @doc """
  Enqueue a query writer payload for processing.
  """
  @spec enqueue(reference(), function(), map(), pid()) :: enqueue_result()
  def enqueue(ref, writer_fun, payload, caller)
      when is_reference(ref) and is_function(writer_fun, 1) and is_pid(caller) do
    message = %Message{
      data: %{
        ref: ref,
        writer: writer_fun,
        payload: payload,
        caller: caller
      },
      acknowledger: NoopAcknowledger.init()
    }

    with {:ok, producer} <- fetch_producer(),
         :ok <- DirectProducer.push(producer, [message]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def enqueue(_ref, _writer_fun, _payload, _caller), do: {:error, :invalid_message}

  @impl true
  def handle_message(
        _,
        %Message{data: %{writer: writer, payload: payload, caller: caller, ref: ref}} = message,
        _state
      ) do
    result = run_writer(writer, payload)

    send(caller, {:writer_complete, ref, payload.date, result})

    message
  end

  def handle_message(_, message, _state), do: message

  defp run_writer(writer, payload) when is_function(writer, 1) do
    try do
      case writer.(payload) do
        {:halt, reason} -> {:halt, reason}
        {:error, reason} -> {:error, reason}
        {:ok, meta} -> {:ok, meta}
        other -> {:ok, other}
      end
    rescue
      exception ->
        Logger.error("Query writer crashed for #{payload.date}: #{Exception.message(exception)}")

        {:error, {:writer_error, Exception.message(exception)}}
    end
  end

  defp run_writer(_, _payload), do: :ok

  defp fetch_producer do
    case Broadway.producer_names(__MODULE__) do
      [producer | _] -> {:ok, producer}
      [] -> {:error, :not_started}
    end
  end
end
