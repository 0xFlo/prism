defmodule GscAnalytics.Workers.SerpPruningWorker do
  @moduledoc """
  Oban worker for automatic pruning of old SERP snapshots.

  ## Features
  - Deletes SERP snapshots older than 7 days
  - Runs daily at 2 AM via Oban cron
  - Logs deletion count for observability
  - Uses indexed :checked_at column for efficiency

  ## Schedule
  Configured in config/config.exs:
  ```elixir
  {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker}
  ```

  ## Manual Execution
      iex> SerpPruningWorker.new(%{}) |> Oban.insert()
      {:ok, %Oban.Job{}}
  """

  use Oban.Worker,
    queue: :maintenance,
    priority: 3

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  require Logger

  @retention_days 7

  @impl Oban.Worker
  def perform(_job) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-@retention_days, :day)

    Logger.info("Starting SERP snapshot pruning",
      retention_days: @retention_days,
      cutoff_date: cutoff_date
    )

    {count, _} =
      from(s in SerpSnapshot, where: s.checked_at < ^cutoff_date)
      |> Repo.delete_all()

    Logger.info("SERP snapshot pruning complete",
      deleted_count: count,
      retention_days: @retention_days
    )

    :ok
  end
end
