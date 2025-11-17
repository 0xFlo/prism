defmodule GscAnalytics.DataSources.GSC.Support.URLPipeline do
  @moduledoc false

  use Broadway

  alias Broadway.Message
  alias GscAnalytics.DataSources.GSC.Core.Sync.URLPhase
  alias GscAnalytics.DataSources.GSC.Support.{DeadLetter, URLProducer}

  @telemetry_prefix [:gsc_analytics, :url_pipeline]

  def run(dates, opts) do
    state = Keyword.fetch!(opts, :state)
    client = Keyword.fetch!(opts, :client)
    max_concurrency = Keyword.get(opts, :max_concurrency, 1)
    owner = self()

    {:ok, agent} =
      Agent.start_link(fn ->
        %{state: state, results: %{}, api_calls: 0}
      end)

    name =
      Module.concat(__MODULE__, :"Pipeline#{System.unique_integer([:positive])}")

    {:ok, pid} =
      Broadway.start_link(__MODULE__,
        name: name,
        context: %{
          agent: agent,
          client: client,
          account_id: state.account_id,
          site_url: state.site_url
        },
        producer: [
          module: {URLProducer, dates: dates, owner: owner}
        ],
        processors: [
          default: [concurrency: max_concurrency]
        ]
      )

    ref = Process.monitor(pid)

    _status =
      receive do
        {:url_pipeline_complete, status} -> status
        {:DOWN, ^ref, _, _, reason} -> {:error, reason}
      end

    :ok = Broadway.stop(name)

    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      0 -> :ok
    end

    data = Agent.get(agent, & &1)
    Agent.stop(agent)

    {data.results, data.api_calls, data.state}
  end

  @impl true
  def handle_message(_, %Message{data: date} = message, context) do
    start = System.monotonic_time(:microsecond)

    status = process_date(date, context)

    duration = System.monotonic_time(:microsecond) - start
    emit_message_metrics(duration, status, context, date)

    case status do
      {:error, _reason} -> Message.failed(message, status)
      _ -> message
    end
  end

  defp process_date(date, %{agent: agent, client: client}) do
    state = Agent.get(agent, & &1.state)

    case URLPhase.command_status(state.job_id) do
      :stop ->
        Agent.update(agent, fn data ->
          %{data | state: URLPhase.mark_stopped(data.state)}
        end)

        {:error, :stopped}

      :pause ->
        URLPhase.wait_for_resume(state.job_id)
        process_date(date, %{agent: agent, client: client})

      :continue ->
        if URLPhase.skip_date?(date, state) do
          Agent.update(agent, fn data ->
            %{data | state: URLPhase.advance_step_with_skip(data.state, date)}
          end)

          :skipped
        else
          case URLPhase.fetch_url_for_date(client, date, state) do
            {:ok, {result, new_state}} ->
              Agent.update(agent, fn data ->
                %{
                  data
                  | state: new_state,
                    results: Map.put(data.results, elem(result, 0), elem(result, 1)),
                    api_calls: data.api_calls + 1
                }
              end)

              :ok

            {:error, reason, {result, new_state}} ->
              DeadLetter.put(:url_pipeline, %{
                account_id: state.account_id,
                site_url: state.site_url,
                date: date,
                reason: inspect(reason)
              })

              Agent.update(agent, fn data ->
                %{
                  data
                  | state: new_state,
                    results: Map.put(data.results, elem(result, 0), elem(result, 1)),
                    api_calls: data.api_calls + 1
                }
              end)

              {:error, reason}
          end
        end
    end
  end

  defp emit_message_metrics(duration_us, status, context, date) do
    measurements = %{
      duration_ms: System.convert_time_unit(duration_us, :microsecond, :millisecond)
    }

    metadata = %{
      status: normalize_status(status),
      date: date,
      account_id: context.account_id,
      site_url: context.site_url
    }

    :telemetry.execute(@telemetry_prefix ++ [:message], measurements, metadata)
  end

  defp normalize_status(:ok), do: :ok
  defp normalize_status(:skipped), do: :skipped
  defp normalize_status({:error, reason}), do: {:error, reason}
  defp normalize_status(_), do: :ok
end
