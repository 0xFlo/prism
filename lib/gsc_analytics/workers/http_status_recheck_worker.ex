defmodule GscAnalytics.Workers.HttpStatusRecheckWorker do
  @moduledoc """
  Oban worker that periodically re-checks stale HTTP status codes.

  This worker runs on a cron schedule to ensure URLs are re-checked based on
  their previous status:
  - Broken links (4xx/5xx): Re-check after 3 days
  - Redirects (3xx): Re-check after 7 days
  - Healthy URLs (2xx): Re-check after 30 days

  Unlike `HttpStatusCheckWorker` which is triggered by GSC syncs for NEW URLs,
  this worker ensures EXISTING URLs are periodically re-validated.

  ## Scheduling

  Configured via `GscAnalytics.Config.AutoSync` module using `HTTP_RECHECK_CRON`
  environment variable (default: once daily at 2 AM UTC).

  ## Multi-Tenancy

  Processes all active workspaces and their properties, enqueueing check jobs
  for each workspace independently to ensure fair resource distribution.
  """

  use Oban.Worker,
    queue: :http_checks,
    priority: 3,
    # Run once, retries would cause duplicate work
    max_attempts: 1

  require Logger

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Workspace
  alias GscAnalytics.Workers.HttpStatusCheckWorker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting periodic HTTP status re-check for all workspaces")

    start_time = System.monotonic_time(:millisecond)

    # Get all active workspaces
    workspaces =
      from(w in Workspace,
        where: not is_nil(w.current_gsc_property_id),
        select: %{account_id: w.id, property_url: w.current_gsc_property_url}
      )
      |> Repo.all()

    Logger.info("Found #{length(workspaces)} active workspaces to re-check")

    # Enqueue stale URL checks for each workspace
    results =
      Enum.map(workspaces, fn workspace ->
        case HttpStatusCheckWorker.enqueue_stale_urls(
               account_id: workspace.account_id,
               property_url: workspace.property_url,
               # Limit to 1000 URLs per workspace to prevent overwhelming the queue
               limit: 1000,
               # Use lower priority since these are periodic re-checks
               priority: 3
             ) do
          {:ok, jobs} ->
            {:ok, length(jobs)}

          {:error, reason} ->
            Logger.error(
              "Failed to enqueue stale URLs for workspace #{workspace.account_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))

    total_jobs =
      results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, count} -> count end)
      |> Enum.sum()

    duration_ms = System.monotonic_time(:millisecond) - start_time

    # Emit telemetry
    :telemetry.execute(
      [:gsc_analytics, :http_recheck, :scheduled_run],
      %{
        duration_ms: duration_ms,
        workspace_count: length(workspaces),
        successful_workspaces: successful,
        total_jobs_enqueued: total_jobs
      },
      %{}
    )

    Logger.info(
      "Periodic HTTP re-check completed: #{successful}/#{length(workspaces)} workspaces, #{total_jobs} jobs enqueued in #{duration_ms}ms"
    )

    :ok
  end
end
