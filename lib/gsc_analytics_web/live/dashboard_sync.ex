defmodule GscAnalyticsWeb.Live.DashboardSync do
  @moduledoc """
  Shared service + formatting helpers that power the DashboardSyncLive view.
  Extracted from the LiveView so we can test/simplify the sync state machine logic.
  """

  import Ecto.Query
  import Phoenix.Component, only: [to_form: 2]

  import GscAnalyticsWeb.Dashboard.HTMLHelpers,
    only: [format_date: 1, days_ago: 1, format_number: 1]

  alias GscAnalytics.Repo
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalytics.Schemas.SyncDay

  @doc """
  Build the sync form struct for the given number of days.
  """
  def build_form(days), do: to_form(%{"days" => days}, as: :sync)

  @doc """
  Parse the submitted day range respecting the configured max.
  """
  def parse_days(%{"days" => "full"}, _max_days), do: {:ok, :full_history}

  def parse_days(%{"days" => days}, max_days) do
    with {value, ""} <- Integer.parse(days),
         true <- value > 0 and value <= max_days do
      {:ok, value}
    else
      _ ->
        {:error, "Please select a valid number of days (1-#{max_days}) or choose full history"}
    end
  end

  def parse_days(_, _max_days), do: {:error, "Please choose a sync range"}

  @doc """
  Validate the currently selected property and return the site URL.
  """
  def configured_site(%{property_url: property_url}) when is_binary(property_url) do
    {:ok, property_url}
  end

  def configured_site(nil),
    do: {:error, "Please select a Search Console property before running a sync."}

  def configured_site(_), do: {:error, "Invalid property configuration."}

  @doc """
  Empty sync info placeholder used to populate failure metadata.
  """
  def empty_sync_info do
    %{last_failure: nil}
  end

  @doc """
  Default progress struct used when there is no active job.
  """
  def new_progress do
    %{
      job_id: nil,
      status: :idle,
      running?: false,
      active?: false,
      percent: 0.0,
      total_steps: 0,
      completed_steps: 0,
      current_step: nil,
      current_date: nil,
      started_at: nil,
      finished_at: nil,
      metadata: %{},
      metrics: empty_metrics(),
      summary: nil,
      error: nil,
      events: [],
      controls: %{can_pause?: false, can_resume?: false, can_stop?: false}
    }
  end

  @doc """
  Convert a SyncProgress job into the assign-friendly progress map.
  Returns {:reset, progress} when the job belongs to another account/property.
  """
  def progress_from_job(nil, _account_id, _property), do: {:ok, new_progress()}

  def progress_from_job(job, current_account_id, current_property) do
    job_account_id = (job.metadata || %{})[:account_id]
    job_property_url = (job.metadata || %{})[:site_url]
    current_property_url = current_property && current_property.property_url

    cond do
      job_account_id && current_account_id && job_account_id != current_account_id ->
        {:reset, new_progress()}

      job_property_url && current_property_url && job_property_url != current_property_url ->
        {:reset, new_progress()}

      true ->
        {:ok, progress_payload(job)}
    end
  end

  defp progress_payload(job) do
    total = job.total_steps || 0
    completed = job.completed_steps || 0
    status = job.status || :running
    active? = status in [:running, :paused, :cancelling]

    percent =
      cond do
        total > 0 ->
          min(completed / total * 100, 100.0) |> Float.round(2)

        status in [:completed, :completed_with_warnings, :cancelled] ->
          100.0

        completed > 0 ->
          100.0

        true ->
          0.0
      end

    %{
      job_id: job.id,
      status: status,
      running?: status in [:running, :cancelling],
      active?: active?,
      percent: percent,
      total_steps: total,
      completed_steps: completed,
      current_step: job.current_step,
      current_date: job.current_date,
      started_at: job.started_at,
      finished_at: job.finished_at,
      metadata: job.metadata || %{},
      metrics: normalize_metrics(job[:metrics]),
      summary: job[:summary],
      error: job[:error],
      controls: %{
        can_pause?: status == :running,
        can_resume?: status == :paused,
        can_stop?: status in [:running, :paused, :cancelling]
      }
    }
  end

  @doc """
  Forward pause/resume/stop actions to SyncProgress based on the job controls.
  """
  def maybe_apply_control(%{job_id: nil}, _action), do: :ok

  def maybe_apply_control(%{job_id: job_id, controls: controls}, :pause) do
    if controls.can_pause?, do: SyncProgress.request_pause(job_id)
  end

  def maybe_apply_control(%{job_id: job_id, controls: controls}, :resume) do
    if controls.can_resume?, do: SyncProgress.resume_job(job_id)
  end

  def maybe_apply_control(%{job_id: job_id, controls: controls}, :stop) do
    if controls.can_stop?, do: SyncProgress.request_stop(job_id)
  end

  def maybe_apply_control(_progress, _action), do: :ok

  @doc """
  Fetch the most recent failure metadata for the given scope/account/property combo.
  """
  def load_sync_info(_scope, account_id, property_url)
      when is_integer(account_id) and is_binary(property_url) do
    empty_sync_info()
    |> Map.put(:last_failure, last_failure(account_id, property_url))
  end

  def load_sync_info(_scope, account_id, _property_url) when is_integer(account_id),
    do: empty_sync_info()

  defp last_failure(account_id, property_url) do
    from(sd in SyncDay,
      where: sd.account_id == ^account_id and sd.site_url == ^property_url,
      where: sd.status in [:failed],
      order_by: [desc: sd.updated_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      %SyncDay{} = failure ->
        %{
          date: failure.date,
          reason: failure.status,
          message: failure.error,
          last_synced_at: failure.last_synced_at,
          age_in_days: failure.date && days_ago(failure.date)
        }
    end
  end

  @doc """
  Badge + label tuple for the current sync status.
  """
  def status_badge(status) do
    case status do
      :running -> {"badge badge-info", "In Progress"}
      :paused -> {"badge badge-warning", "Paused"}
      :cancelling -> {"badge badge-warning", "Stopping"}
      :cancelled -> {"badge badge-ghost", "Cancelled"}
      :completed -> {"badge badge-success", "Completed"}
      :completed_with_warnings -> {"badge badge-warning", "Completed with warnings"}
      :failed -> {"badge badge-error", "Failed"}
      _ -> {"badge badge-ghost", "Idle"}
    end
  end

  @doc """
  Human readable caption under the progress bar.
  """
  def progress_caption(progress)

  def progress_caption(%{
        status: :running,
        current_step: step,
        total_steps: total,
        current_date: date,
        metrics: metrics
      }) do
    date_label = format_date_safe(date)
    base = "Processing day ##{step} of #{max(total, 1)} (#{date_label})"

    metrics_summary =
      [
        rows_phrase(metrics[:total_rows]),
        http_batch_phrase(metrics[:total_query_http_batches]),
        query_sub_request_phrase(metrics[:total_query_sub_requests])
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    if metrics_summary == "" do
      base
    else
      base <> " · " <> metrics_summary
    end
  end

  def progress_caption(%{status: :paused, completed_steps: completed, metrics: metrics}) do
    [
      "Paused after processing #{completed} day(s)",
      rows_phrase(metrics[:total_rows]),
      http_batch_phrase(metrics[:total_query_http_batches]),
      query_sub_request_phrase(metrics[:total_query_sub_requests])
    ]
    |> Enum.reject(&is_nil_or_empty?/1)
    |> Enum.join(" · ")
  end

  def progress_caption(%{status: :cancelling, completed_steps: completed, metrics: metrics}) do
    [
      "Stopping sync – #{completed} day(s) processed so far",
      rows_phrase(metrics[:total_rows]),
      http_batch_phrase(metrics[:total_query_http_batches]),
      query_sub_request_phrase(metrics[:total_query_sub_requests])
    ]
    |> Enum.reject(&is_nil_or_empty?/1)
    |> Enum.join(" · ")
  end

  def progress_caption(%{status: status, summary: summary})
      when status in [:completed, :completed_with_warnings] and is_map(summary) do
    days = summary[:days_processed] || 0
    rows = summary[:total_rows] || 0
    query_sub_requests = summary[:total_query_sub_requests] || 0
    query_http_batches = summary[:total_query_http_batches] || 0
    urls = summary[:total_urls] || 0
    skipped = summary[:skipped_days] || 0

    headline =
      if skipped > 0 do
        "Processed #{days} day(s) (#{skipped} skipped)"
      else
        "Processed #{days} day(s)"
      end

    metrics =
      [
        rows_phrase(rows),
        http_batch_phrase(query_http_batches),
        query_sub_request_phrase(query_sub_requests),
        url_phrase(urls)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    if metrics == "" do
      headline
    else
      headline <> " · " <> metrics
    end
  end

  def progress_caption(%{status: :cancelled, summary: summary}) when is_map(summary) do
    days = summary[:days_processed] || 0
    "Cancelled after processing #{days} day(s)"
  end

  def progress_caption(%{status: :cancelled}), do: "Sync cancelled"

  def progress_caption(%{status: :failed, summary: summary, error: error}) when is_map(summary) do
    failure_date = summary[:failed_on] || summary[:halt_on]

    base =
      case failure_date do
        %Date{} -> "Sync failed on #{format_date_safe(failure_date)}"
        %DateTime{} -> "Sync failed on #{format_date_safe(failure_date)}"
        _ -> "Sync failed"
      end

    message = truncate_error(error || summary[:error], 80)

    metrics =
      [
        rows_phrase(summary[:total_rows]),
        http_batch_phrase(summary[:total_query_http_batches]),
        query_sub_request_phrase(summary[:total_query_sub_requests])
      ]
      |> Enum.reject(&is_nil_or_empty?/1)
      |> Enum.join(" · ")

    [base, message, metrics]
    |> Enum.reject(&is_nil_or_empty?/1)
    |> Enum.join(" – ")
  end

  def progress_caption(%{status: :failed, error: error}) do
    message = truncate_error(error, 80)

    case message do
      nil -> "Sync failed"
      _ -> "Sync failed – #{message}"
    end
  end

  def progress_caption(_), do: "No active sync"

  @doc """
  Date helper used by the template for the failure card.
  """
  def progress_failure_date(%{summary: summary}) when is_map(summary),
    do: summary[:failed_on] || summary[:halt_on]

  def progress_failure_date(_), do: nil

  @doc """
  Failure reason string.
  """
  def progress_failure_raw_message(%{error: error, summary: summary}) do
    cond do
      is_binary(error) and error != "" -> error
      is_map(summary) and is_binary(summary[:error]) and summary[:error] != "" -> summary[:error]
      true -> nil
    end
  end

  def progress_failure_raw_message(_), do: nil

  def format_timestamp(nil), do: "—"
  def format_timestamp(%DateTime{} = ts), do: Calendar.strftime(ts, "%b %d • %H:%M UTC")
  def format_timestamp(_), do: "—"

  def sync_button_icon_class(%{running?: true}), do: "h-5 w-5 animate-spin"
  def sync_button_icon_class(_), do: "h-5 w-5"

  # Internal helpers ---------------------------------------------------------

  defp empty_metrics do
    %{
      total_rows: 0,
      total_query_sub_requests: 0,
      total_query_http_batches: 0,
      total_url_requests: 0,
      total_urls: 0,
      total_api_calls: 0
    }
  end

  defp normalize_metrics(nil), do: empty_metrics()

  defp normalize_metrics(metrics) do
    Map.merge(empty_metrics(), metrics || %{})
  end

  def rows_phrase(value), do: human_count(value, {"query row", "query rows"})
  def query_batch_phrase(value), do: human_count(value, {"query batch", "query batches"})

  def query_sub_request_phrase(value),
    do: human_count(value, {"query sub-request", "query sub-requests"})

  def http_batch_phrase(value), do: human_count(value, {"HTTP batch", "HTTP batches"})
  def url_phrase(value), do: human_count(value, {"URL", "URLs"})
  def api_call_phrase(value), do: human_count(value, {"API call", "API calls"})

  def format_date_safe(nil), do: "–"
  def format_date_safe(%Date{} = date), do: format_date(date)

  def format_date_safe(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> format_date()

  def format_date_safe(value), do: to_string(value)

  def truncate_error(nil, _limit), do: nil

  def truncate_error(error, limit) do
    error
    |> to_string()
    |> String.trim()
    |> case do
      "" ->
        nil

      message ->
        if String.length(message) > limit,
          do: String.slice(message, 0, limit) <> "…",
          else: message
    end
  end

  def format_duration(nil), do: "—"

  def format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms} ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  def format_duration(_), do: "—"

  defp human_count(value, {_singular, _plural}) when value in [nil, :undefined], do: nil

  defp human_count(value, {singular, plural}) when is_integer(value) do
    cond do
      value <= 0 -> nil
      value == 1 -> "1 #{singular}"
      true -> "#{format_number(value)} #{plural}"
    end
  end

  defp human_count(value, labels) when is_float(value), do: human_count(round(value), labels)
  defp human_count(_value, _labels), do: nil

  defp is_nil_or_empty?(value) when value in [nil, ""], do: true
  defp is_nil_or_empty?(_value), do: false
end
