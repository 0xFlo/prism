defmodule GscAnalyticsWeb.DashboardSyncLive do
  use GscAnalyticsWeb, :live_view

  import Ecto.Query

  import GscAnalyticsWeb.Dashboard.HTMLHelpers,
    only: [format_date: 1, days_ago: 1, format_number: 1]

  alias GscAnalytics.{Accounts, Repo}
  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalytics.Schemas.{Performance, TimeSeries}
  alias GscAnalyticsWeb.Live.AccountHelpers

  @max_days 540
  @default_days "30"
  @day_options [
    {"Full history (auto)", "full"},
    {"Last 7 days", "7"},
    {"Last 14 days", "14"},
    {"Last 30 days", "30"},
    {"Last 60 days", "60"},
    {"Last 90 days", "90"},
    {"Last 180 days", "180"}
  ]

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Subscribe to PubSub only on connected socket (not initial render)
    if connected?(socket), do: SyncProgress.subscribe()

    progress_state = SyncProgress.current_state()

    socket = assign(socket, :current_scope, nil)
    {socket, account} = AccountHelpers.init_account_assigns(socket, params)

    socket =
      socket
      |> assign(:current_path, "/dashboard/sync")
      |> assign(:page_title, "Sync Status")
      |> assign(:day_options, @day_options)
      |> assign(:form, build_form(@default_days))
      |> assign(:sync_info, load_sync_info(account.id))
      |> assign_progress(progress_state)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> assign(:sync_info, load_sync_info(socket.assigns.current_account_id))

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_sync", %{"sync" => params}, %{assigns: assigns} = socket) do
    case parse_days(params) do
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:ok, :full_history} ->
        if assigns.progress.active? do
          {:noreply, put_flash(socket, :error, "A sync is already in progress")}
        else
          account_id = socket.assigns.current_account_id
          site_url = configured_site(account_id)

          Task.start(fn -> Sync.sync_full_history(site_url, account_id: account_id) end)

          form = build_form("full")

          {:noreply,
           socket
           |> assign(:form, form)
           |> put_flash(:info, "Full history sync started")}
        end

      {:ok, days} when is_integer(days) ->
        if assigns.progress.active? do
          {:noreply, put_flash(socket, :error, "A sync is already in progress")}
        else
          account_id = socket.assigns.current_account_id
          site_url = configured_site(account_id)

          Task.start(fn -> Sync.sync_last_n_days(site_url, days, account_id: account_id) end)

          form = build_form(Integer.to_string(days))

          {:noreply,
           socket
           |> assign(:form, form)
           |> put_flash(:info, "Sync started for the last #{days} days")}
        end
    end
  end

  @impl true
  def handle_event("start_sync", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/sync?#{[account_id: account_id]}")}
  end

  @impl true
  def handle_event("pause_sync", _params, %{assigns: %{progress: progress}} = socket) do
    maybe_apply_control(progress, :pause)
    {:noreply, socket}
  end

  @impl true
  def handle_event("resume_sync", _params, %{assigns: %{progress: progress}} = socket) do
    maybe_apply_control(progress, :resume)
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_sync", _params, %{assigns: %{progress: progress}} = socket) do
    maybe_apply_control(progress, :stop)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_progress, %{job: job} = payload}, socket) do
    socket = assign_progress(socket, job)

    socket =
      case payload.type do
        :finished ->
          assign(socket, :sync_info, load_sync_info(socket.assigns.current_account_id))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Helpers

  defp assign_progress(socket, nil) do
    socket
    |> assign(:progress, %{
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
    })
  end

  defp assign_progress(socket, job) do
    current_account_id = socket.assigns.current_account_id
    job_account_id = (job.metadata || %{})[:account_id]

    if job_account_id && current_account_id && job_account_id != current_account_id do
      assign_progress(socket, nil)
    else
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

      socket
      |> assign(:progress, %{
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
      })
    end
  end

  defp build_form(days) do
    to_form(%{"days" => days}, as: :sync)
  end

  defp parse_days(%{"days" => "full"}), do: {:ok, :full_history}

  defp parse_days(%{"days" => days}) do
    with {value, ""} <- Integer.parse(days),
         true <- value > 0 and value <= @max_days do
      {:ok, value}
    else
      _ ->
        {:error, "Please select a valid number of days (1-#{@max_days}) or choose full history"}
    end
  end

  defp parse_days(_), do: {:error, "Please choose a sync range"}

  defp maybe_apply_control(%{job_id: nil}, _action), do: :ok

  defp maybe_apply_control(%{job_id: job_id, controls: controls}, :pause) do
    if controls.can_pause?, do: SyncProgress.request_pause(job_id)
  end

  defp maybe_apply_control(%{job_id: job_id, controls: controls}, :resume) do
    if controls.can_resume?, do: SyncProgress.resume_job(job_id)
  end

  defp maybe_apply_control(%{job_id: job_id, controls: controls}, :stop) do
    if controls.can_stop?, do: SyncProgress.request_stop(job_id)
  end

  defp maybe_apply_control(_progress, _action), do: :ok

  defp configured_site(account_id) do
    case Accounts.gsc_default_property(account_id) do
      {:ok, property} -> property
      {:error, _reason} -> "sc-domain:example.com"
    end
  end

  defp load_sync_info(account_id) when is_integer(account_id) do
    last_fetch_query =
      from(p in Performance,
        where: p.account_id == ^account_id,
        select: max(p.fetched_at)
      )

    date_range_query =
      from(ts in TimeSeries,
        where: ts.account_id == ^account_id,
        select: %{
          min_date: min(ts.date),
          max_date: max(ts.date),
          total_records: count()
        }
      )

    last_fetched = Repo.one(last_fetch_query)
    date_info = Repo.one(date_range_query) || %{min_date: nil, max_date: nil, total_records: 0}

    %{
      last_sync: last_fetched,
      earliest_date: date_info.min_date,
      latest_date: date_info.max_date,
      total_records: date_info.total_records,
      days_available: calculate_days_available(date_info)
    }
  end

  defp calculate_days_available(%{min_date: min, max_date: max})
       when not is_nil(min) and not is_nil(max) do
    Date.diff(max, min) + 1
  end

  defp calculate_days_available(_), do: 0

  defp format_events(events) do
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
    base = [event.type, event.step, event.timestamp]

    base
    |> Enum.map(fn
      nil -> "_"
      %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
      other -> to_string(other)
    end)
    |> Enum.join("-")
  end

  defp event_label(%{type: :step_started, date: date, step: step}) do
    "Starting day ##{step}: #{format_date_safe(date)}"
  end

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
      [
        rows_phrase(rows) || "0 query rows",
        query_batch_phrase(query_batches),
        url_phrase(urls)
      ]
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

  defp event_label(%{type: :step_completed, status: :skipped, date: date, step: step}) do
    "Day ##{step} (#{format_date_safe(date)}) already synced – skipped"
  end

  defp event_label(%{type: :paused}) do
    "Sync paused by user"
  end

  defp event_label(%{type: :resumed}) do
    "Sync resumed"
  end

  defp event_label(%{type: :stopping}) do
    "Cancellation requested"
  end

  defp event_label(%{type: :finished, summary: summary, error: nil}) when is_map(summary) do
    days = summary[:days_processed] || 0
    duration = summary[:duration_ms] |> format_duration()
    "Sync finished – #{days} day(s) processed in #{duration}"
  end

  defp event_label(%{type: :finished, error: error}) do
    message = error && String.slice(to_string(error), 0, 120)
    "Sync failed: #{message}"
  end

  defp event_label(%{type: :started}) do
    "Sync job queued"
  end

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

  defp event_badge_label(%{type: :step_completed, status: :ok}), do: "Completed"
  defp event_badge_label(%{type: :step_completed, status: :error}), do: "Errors"
  defp event_badge_label(%{type: :step_completed, status: :skipped}), do: "Skipped"
  defp event_badge_label(%{type: :step_started}), do: "Running"
  defp event_badge_label(%{type: :paused}), do: "Paused"
  defp event_badge_label(%{type: :resumed}), do: "Resumed"
  defp event_badge_label(%{type: :stopping}), do: "Stopping"
  defp event_badge_label(%{type: :finished, error: error}) when not is_nil(error), do: "Failed"
  defp event_badge_label(%{type: :finished, summary: summary}) when is_map(summary), do: "Summary"
  defp event_badge_label(%{type: :started}), do: "Queued"
  defp event_badge_label(_), do: nil

  defp format_date_safe(nil), do: "–"
  defp format_date_safe(%Date{} = date), do: format_date(date)

  defp format_date_safe(%DateTime{} = datetime),
    do: datetime |> DateTime.to_date() |> format_date()

  defp format_date_safe(value), do: to_string(value)

  defp format_duration(nil), do: "—"

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms} ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_duration(_), do: "—"

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

  defp human_count(value, {_singular, _plural}) when value in [nil, :undefined], do: nil

  defp human_count(value, {singular, plural}) when is_integer(value) do
    cond do
      value <= 0 -> nil
      value == 1 -> "1 #{singular}"
      true -> "#{format_number(value)} #{plural}"
    end
  end

  defp human_count(value, labels) when is_float(value) do
    human_count(round(value), labels)
  end

  defp human_count(_value, _labels), do: nil

  defp is_nil_or_empty?(value) when value in [nil, ""], do: true
  defp is_nil_or_empty?(_value), do: false

  defp rows_phrase(value), do: human_count(value, {"query row", "query rows"})
  defp query_batch_phrase(value), do: human_count(value, {"query batch", "query batches"})

  defp query_sub_request_phrase(value),
    do: human_count(value, {"query sub-request", "query sub-requests"})

  defp http_batch_phrase(value), do: human_count(value, {"HTTP batch", "HTTP batches"})
  defp url_request_phrase(value), do: human_count(value, {"URL request", "URL requests"})
  defp url_phrase(value), do: human_count(value, {"URL", "URLs"})
  defp api_call_phrase(value), do: human_count(value, {"API call", "API calls"})

  defp status_badge(status) do
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

  defp progress_caption(%{
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

  defp progress_caption(%{status: :paused, completed_steps: completed, metrics: metrics}) do
    bits =
      [
        "Paused after processing #{completed} day(s)",
        rows_phrase(metrics[:total_rows]),
        http_batch_phrase(metrics[:total_query_http_batches]),
        query_sub_request_phrase(metrics[:total_query_sub_requests])
      ]
      |> Enum.reject(&is_nil_or_empty?/1)

    Enum.join(bits, " · ")
  end

  defp progress_caption(%{status: :cancelling, completed_steps: completed, metrics: metrics}) do
    bits =
      [
        "Stopping sync – #{completed} day(s) processed so far",
        rows_phrase(metrics[:total_rows]),
        http_batch_phrase(metrics[:total_query_http_batches]),
        query_sub_request_phrase(metrics[:total_query_sub_requests])
      ]
      |> Enum.reject(&is_nil_or_empty?/1)

    Enum.join(bits, " · ")
  end

  defp progress_caption(%{status: status, summary: summary})
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

  defp progress_caption(%{status: :cancelled, summary: summary}) when is_map(summary) do
    days = summary[:days_processed] || 0
    "Cancelled after processing #{days} day(s)"
  end

  defp progress_caption(%{status: :cancelled}), do: "Sync cancelled"

  defp progress_caption(%{status: :failed, error: error}) do
    message = error && String.slice(to_string(error), 0, 120)
    "Sync failed: #{message || "unknown error"}"
  end

  defp progress_caption(_), do: "No active sync"

  defp event_tag_class(:success), do: "badge badge-success badge-sm"
  defp event_tag_class(:error), do: "badge badge-error badge-sm"
  defp event_tag_class(_), do: "badge badge-info badge-sm"

  defp event_marker_class(:success), do: "bg-emerald-500"
  defp event_marker_class(:error), do: "bg-rose-500"
  defp event_marker_class(:info), do: "bg-sky-500"
  defp event_marker_class(_), do: "bg-slate-400"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(%DateTime{} = ts) do
    Calendar.strftime(ts, "%b %d • %H:%M UTC")
  end

  defp format_timestamp(_), do: "—"

  defp sync_button_icon_class(%{running?: true}), do: "h-5 w-5 animate-spin"
  defp sync_button_icon_class(_), do: "h-5 w-5"
end
