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
  alias GscAnalytics.Schemas.{Performance, SyncDay, TimeSeries}

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
  Empty sync info placeholder shown before we hydrate metrics from the DB.
  """
  def empty_sync_info do
    %{
      last_sync: nil,
      earliest_date: nil,
      latest_date: nil,
      total_records: 0,
      days_available: 0,
      last_failure: nil
    }
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
      events: format_events(job.events || []),
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
  Fetch sync metadata for the given scope/account/property combo.
  """
  def load_sync_info(_scope, account_id, property_url)
      when is_integer(account_id) and is_binary(property_url) do
    result =
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id and ts.property_url == ^property_url,
        select: %{
          earliest_date: min(ts.date),
          latest_date: max(ts.date),
          total_records: count(ts.date)
        }
      )
      |> Repo.one()

    earliest_date = result && result.earliest_date
    latest_date = result && result.latest_date

    last_sync =
      from(perf in Performance,
        where: perf.account_id == ^account_id and perf.property_url == ^property_url,
        select: max(perf.fetched_at)
      )
      |> Repo.one()

    last_failure = last_failure(account_id, property_url)

    %{
      last_sync: last_sync,
      earliest_date: earliest_date,
      latest_date: latest_date,
      total_records: result && result.total_records,
      days_available: calculate_days_available(earliest_date, latest_date),
      last_failure: last_failure
    }
  end

  def load_sync_info(_scope, account_id, _property_url) when is_integer(account_id),
    do: empty_sync_info()

  defp last_failure(account_id, property_url) do
    from(sd in SyncDay,
      where: sd.account_id == ^account_id and sd.property_url == ^property_url,
      where: sd.status in ["failed", "halted"],
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

  defp calculate_days_available(%Date{} = min, %Date{} = max), do: Date.diff(max, min) + 1
  defp calculate_days_available(_min, _max), do: 0

  @doc """
  Format and truncate the most recent events emitted by SyncProgress.
  """
  def format_events(events) do
    events
    |> Enum.take(12)
    |> Enum.map(&format_event/1)
  end

  defp format_event(event) do
    %{
      key: event_key(event),
      type: event.type,
      step: event.step,
      date: event.date,
      status: event.status,
      urls: event.urls,
      rows: event.rows,
      query_batches: event.query_batches,
      url_requests: event.url_requests,
      api_calls: event.api_calls,
      duration_ms: event.duration_ms,
      message: event.message,
      timestamp: event.timestamp,
      summary: event.summary,
      error: event.error,
      label: event_label(event),
      tone: event_tone(event)
    }
  end

  defp event_key(event) do
    [event.type, event.step, event.timestamp]
    |> Enum.map(fn
      nil -> "_"
      %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
      other -> to_string(other)
    end)
    |> Enum.join("-")
  end

  defp event_label(%{type: :step_started, date: date, step: step}),
    do: "Starting day ##{step}: #{format_date_safe(date)}"

  defp event_label(%{
         type: :step_completed,
         status: :ok,
         date: date,
         rows: rows,
         query_batches: query_batches,
         urls: urls,
         step: step
       }) do
    pieces =
      [rows_phrase(rows) || "0 query rows", query_batch_phrase(query_batches), url_phrase(urls)]
      |> Enum.reject(&is_nil/1)

    summary = Enum.join(pieces, " · ")
    "Finished day ##{step} (#{format_date_safe(date)}) – #{summary}"
  end

  defp event_label(%{
         type: :step_completed,
         status: :error,
         date: date,
         rows: rows,
         query_batches: query_batches,
         urls: urls,
         step: step
       }) do
    details =
      [rows_phrase(rows), query_batch_phrase(query_batches), url_phrase(urls)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    if details == "" do
      "Day ##{step} (#{format_date_safe(date)}) completed with errors"
    else
      "Day ##{step} (#{format_date_safe(date)}) completed with errors – #{details}"
    end
  end

  defp event_label(%{type: :step_completed, status: :skipped, date: date, step: step}),
    do: "Day ##{step} (#{format_date_safe(date)}) already synced – skipped"

  defp event_label(%{type: :paused}), do: "Sync paused by user"
  defp event_label(%{type: :resumed}), do: "Sync resumed"
  defp event_label(%{type: :stopping}), do: "Cancellation requested"

  defp event_label(%{type: :finished, summary: summary, error: error}) when is_map(summary) do
    cond do
      is_nil(error) and is_nil(summary[:error]) ->
        days = summary[:days_processed] || 0
        duration = summary[:duration_ms] |> format_duration()
        "Sync finished – #{days} day(s) processed in #{duration}"

      true ->
        failure_date = summary[:failed_on] || summary[:halt_on]

        base =
          case failure_date do
            %Date{} -> "Sync failed on #{format_date_safe(failure_date)}"
            %DateTime{} -> "Sync failed on #{format_date_safe(failure_date)}"
            _ -> "Sync failed"
          end

        message = truncate_error(error || summary[:error], 120)

        metrics =
          [
            rows_phrase(summary[:total_rows]),
            http_batch_phrase(summary[:total_query_http_batches]),
            query_sub_request_phrase(summary[:total_query_sub_requests])
          ]
          |> Enum.reject(&is_nil_or_empty?/1)
          |> Enum.join(" · ")

        details =
          [message, metrics]
          |> Enum.reject(&is_nil_or_empty?/1)
          |> Enum.join(" – ")

        if details == "" do
          base
        else
          "#{base} – #{details}"
        end
    end
  end

  defp event_label(%{type: :finished, error: error}) do
    message = truncate_error(error, 120)
    if message, do: "Sync failed – #{message}", else: "Sync failed"
  end

  defp event_label(%{type: :started}), do: "Sync job queued"
  defp event_label(_), do: "Update received"

  defp event_tone(%{type: :step_completed, status: :error}), do: :error
  defp event_tone(%{type: :step_completed, status: :skipped}), do: :info
  defp event_tone(%{type: :finished, error: error}) when not is_nil(error), do: :error
  defp event_tone(%{type: :stopping}), do: :warning
  defp event_tone(%{type: :paused}), do: :info
  defp event_tone(%{type: :resumed}), do: :success
  defp event_tone(%{type: :step_completed}), do: :success
  defp event_tone(%{type: :step_started}), do: :info
  defp event_tone(%{type: :finished, summary: summary}) when is_map(summary), do: :success
  defp event_tone(_), do: :info

  @doc """
  Badge class for the event timeline.
  """
  def event_badge_label(%{type: :step_completed, status: :ok}), do: "Completed"
  def event_badge_label(%{type: :step_completed, status: :error}), do: "Errors"
  def event_badge_label(%{type: :step_completed, status: :skipped}), do: "Skipped"
  def event_badge_label(%{type: :step_started}), do: "Running"
  def event_badge_label(%{type: :paused}), do: "Paused"
  def event_badge_label(%{type: :resumed}), do: "Resumed"
  def event_badge_label(%{type: :stopping}), do: "Stopping"
  def event_badge_label(%{type: :finished, error: error}) when not is_nil(error), do: "Failed"
  def event_badge_label(%{type: :finished, summary: summary}) when is_map(summary), do: "Summary"
  def event_badge_label(%{type: :started}), do: "Queued"
  def event_badge_label(_), do: nil

  def event_tag_class(:success), do: "badge badge-success badge-sm"
  def event_tag_class(:error), do: "badge badge-error badge-sm"
  def event_tag_class(_), do: "badge badge-info badge-sm"

  def event_marker_class(:success), do: "bg-emerald-500"
  def event_marker_class(:error), do: "bg-rose-500"
  def event_marker_class(:info), do: "bg-sky-500"
  def event_marker_class(_), do: "bg-slate-400"

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
  def url_request_phrase(value), do: human_count(value, {"URL request", "URL requests"})
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
