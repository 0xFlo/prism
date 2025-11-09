defmodule GscAnalyticsWeb.DashboardCrawlerLive do
  @moduledoc """
  LiveView for URL health monitoring and HTTP status checking.

  Provides a real-time interface for running HTTP checks on URLs,
  tracking progress, and viewing results and history.
  """

  use GscAnalyticsWeb, :live_view
  import Ecto.Query, only: [where: 3]

  import GscAnalyticsWeb.Dashboard.HTMLHelpers,
    only: [format_number: 1, format_datetime: 1]

  import GscAnalyticsWeb.Components.DashboardComponents,
    only: [property_selector: 1]

  alias GscAnalytics.Crawler
  alias GscAnalyticsWeb.Live.AccountHelpers

  @filter_options [
    {"Stale URLs (unchecked or >7 days old)", "stale"},
    {"All URLs", "all"},
    {"Broken Links (4xx/5xx)", "broken"},
    {"Redirected URLs (3xx)", "redirected"}
  ]

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Subscribe to PubSub only on connected socket
    if connected?(socket) do
      Crawler.subscribe()
      # Subscribe to telemetry for background HTTP check updates
      :ok =
        :telemetry.attach(
          "dashboard-http-checks-#{self()}",
          [:gsc_analytics, :http_check, :batch_complete],
          &__MODULE__.handle_telemetry/4,
          socket.id
        )
    end

    current_job = Crawler.current_progress()
    history = Crawler.get_history()
    queue_stats = get_queue_stats()

    {socket, account, property} = AccountHelpers.init_account_and_property_assigns(socket, params)

    # Redirect to Settings if no workspaces exist
    if is_nil(account) do
      {:ok,
       socket
       |> put_flash(
         :info,
         "Please add a Google Search Console workspace to get started."
       )
       |> redirect(to: ~p"/users/settings")}
    else
      %{label: property_label, favicon_url: property_favicon_url, url: property_url} =
        property_context(property)

      problem_urls = fetch_problem_urls(account.id, property_url)
      global_stats = fetch_global_stats(account.id, property_url)
      property_id = property && property.id
      scoped_job = scoped_job_for_selection(current_job, account.id, property_id)
      history_for_scope = filter_history_for_scope(history, account.id, property_id)

      socket =
        socket
        |> assign(:current_path, "/dashboard/crawler")
        |> assign(:page_title, "URL Health Monitor")
        |> assign(:filter_options, @filter_options)
        |> assign(:form, build_form("stale"))
        |> assign(:history, history_for_scope)
        |> assign(:problem_urls, problem_urls)
        |> assign(:selected_status_filter, "all")
        |> assign(:global_stats, global_stats)
        |> assign(:property_label, property_label)
        |> assign(:property_favicon_url, property_favicon_url)
        |> assign(:queue_stats, queue_stats)
        |> assign_progress(scoped_job)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params)

    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property

    property_id = property && property.id

    history =
      Crawler.get_history()
      |> filter_history_for_scope(account_id, property_id)

    scoped_job =
      Crawler.current_progress()
      |> scoped_job_for_selection(account_id, property_id)

    %{label: property_label, favicon_url: property_favicon_url, url: property_url} =
      property_context(property)

    socket =
      socket
      |> assign(
        :problem_urls,
        fetch_problem_urls(account_id, property_url, socket.assigns.selected_status_filter)
      )
      |> assign(:global_stats, fetch_global_stats(account_id, property_url))
      |> assign(:property_label, property_label)
      |> assign(:property_favicon_url, property_favicon_url)
      |> assign(:history, history)
      |> assign_progress(scoped_job)

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_check", %{"check" => params}, %{assigns: assigns} = socket) do
    filter = parse_filter(params["filter"] || "stale")

    cond do
      is_nil(assigns.current_property) ->
        {:noreply,
         socket
         |> put_flash(:error, "Select a property before running the crawler.")}

      assigns.progress.running? ->
        {:noreply, put_flash(socket, :error, "A check is already in progress")}

      true ->
        # Start check in background task
        account_id = socket.assigns.current_account_id
        property = socket.assigns.current_property
        property_url = property && property.property_url

        Task.start(fn ->
          Crawler.check_all(
            account_id: account_id,
            property_id: property && property.id,
            property_url: property_url,
            property_label: socket.assigns.property_label,
            filter: filter
          )
        end)

        form = build_form(Atom.to_string(filter))

        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:info, "HTTP status check started")}
    end
  end

  @impl true
  def handle_event("start_check", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_problems", %{"status" => status}, socket) do
    account_id = socket.assigns.current_account_id
    property = socket.assigns.current_property
    property_url = property && property.property_url
    problem_urls = fetch_problem_urls(account_id, property_url, status)

    {:noreply,
     socket
     |> assign(:problem_urls, problem_urls)
     |> assign(:selected_status_filter, status)}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/crawler?#{[account_id: account_id]}")}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/crawler?#{[property_id: property_id]}")}
  end

  def handle_event("switch_property", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:crawler_progress, %{type: :started, job: job}}, socket) do
    if job_matches_scope?(
         job,
         socket.assigns.current_account_id,
         socket.assigns.current_property_id
       ) do
      {:noreply, assign_progress(socket, job)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:crawler_progress, %{type: :update, job: job}}, socket) do
    if job_matches_scope?(
         job,
         socket.assigns.current_account_id,
         socket.assigns.current_property_id
       ) do
      {:noreply, assign_progress(socket, job)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:crawler_progress, %{type: :finished, job: job}}, socket) do
    if job_matches_scope?(
         job,
         socket.assigns.current_account_id,
         socket.assigns.current_property_id
       ) do
      account_id = socket.assigns.current_account_id
      property = socket.assigns.current_property
      property_url = property && property.property_url
      property_id = socket.assigns.current_property_id

      history =
        Crawler.get_history()
        |> filter_history_for_scope(account_id, property_id)

      # Reload problem URLs with current filter to show updated results
      problem_urls =
        fetch_problem_urls(account_id, property_url, socket.assigns.selected_status_filter)

      # Refresh global stats to reflect latest database state
      global_stats = fetch_global_stats(account_id, property_url)

      socket =
        socket
        |> assign_progress(job)
        |> assign(:history, history)
        |> assign(:problem_urls, problem_urls)
        |> assign(:global_stats, global_stats)
        |> put_flash(:info, "HTTP status check completed")

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:telemetry_update, socket_id}, socket) when socket.id == socket_id do
    # Update queue stats when telemetry event fires
    queue_stats = get_queue_stats()
    {:noreply, assign(socket, :queue_stats, queue_stats)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp assign_progress(socket, nil) do
    assign(socket, :progress, %{
      job_id: nil,
      running?: false,
      total_urls: 0,
      checked: 0,
      percent: 0.0,
      rate: nil,
      started_at: nil,
      finished_at: nil,
      duration_ms: nil,
      status_counts: %{
        "2xx" => 0,
        "3xx" => 0,
        "4xx" => 0,
        "5xx" => 0,
        "errors" => 0
      }
    })
  end

  defp assign_progress(socket, job) do
    total = job.total_urls || 0
    checked = job.checked || 0
    running? = is_nil(Map.get(job, :finished_at))

    percent =
      if total > 0 do
        min(checked / total * 100, 100.0) |> Float.round(2)
      else
        0.0
      end

    # Calculate crawl speed (URLs per second)
    rate = calculate_crawl_rate(job, checked, running?)

    assign(socket, :progress, %{
      job_id: job.id,
      running?: running?,
      total_urls: total,
      checked: checked,
      percent: percent,
      rate: rate,
      started_at: job.started_at,
      finished_at: Map.get(job, :finished_at),
      duration_ms: Map.get(job, :duration_ms),
      status_counts:
        job.status_counts ||
          %{
            "2xx" => 0,
            "3xx" => 0,
            "4xx" => 0,
            "5xx" => 0,
            "errors" => 0
          }
    })
  end

  defp calculate_crawl_rate(_job, checked, _running?) when checked == 0, do: nil

  defp calculate_crawl_rate(job, checked, running?) do
    elapsed_ms =
      if running? do
        # For running jobs, calculate elapsed time from start to now
        DateTime.diff(DateTime.utc_now(), job.started_at, :millisecond)
      else
        # For finished jobs, use stored duration
        Map.get(job, :duration_ms, 0)
      end

    if elapsed_ms > 0 do
      # Convert to URLs per second
      (checked / (elapsed_ms / 1000)) |> Float.round(2)
    else
      nil
    end
  end

  defp property_context(nil) do
    %{label: nil, favicon_url: nil, url: nil}
  end

  defp property_context(property) do
    property_url = property && Map.get(property, :property_url)

    label =
      case Map.get(property, :display_name) do
        display_name when is_binary(display_name) ->
          trimmed = String.trim(display_name)
          if trimmed == "", do: AccountHelpers.display_property_label(property_url), else: trimmed

        _ ->
          AccountHelpers.display_property_label(property_url)
      end

    %{
      label: label,
      favicon_url: property && Map.get(property, :favicon_url),
      url: property_url
    }
  end

  defp build_form(filter) do
    to_form(%{"filter" => filter}, as: :check)
  end

  defp parse_filter("all"), do: :all
  defp parse_filter("stale"), do: :stale
  defp parse_filter("broken"), do: :broken
  defp parse_filter("redirected"), do: :redirected
  defp parse_filter(_), do: :stale

  defp format_duration(nil), do: "—"

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms < 1000 -> "#{ms} ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_duration(_), do: "—"

  defp format_rate(nil), do: "—"

  defp format_rate(rate) when is_float(rate) do
    cond do
      rate >= 10 -> "#{Float.round(rate, 1)} URLs/sec"
      rate >= 1 -> "#{Float.round(rate, 2)} URLs/sec"
      rate > 0 -> "#{Float.round(rate * 60, 1)} URLs/min"
      true -> "—"
    end
  end

  defp format_rate(_), do: "—"

  defp status_code_badge_class(status) when status >= 200 and status < 300,
    do: "badge badge-success"

  defp status_code_badge_class(status) when status >= 300 and status < 400,
    do: "badge badge-warning"

  defp status_code_badge_class(status) when status >= 400 and status < 500,
    do: "badge badge-error"

  defp status_code_badge_class(status) when status >= 500, do: "badge badge-error"
  defp status_code_badge_class(_), do: "badge badge-ghost"

  defp fetch_problem_urls(account_id, property_url, status_filter \\ "all")
  defp fetch_problem_urls(nil, _property_url, _status_filter), do: []

  defp fetch_problem_urls(account_id, property_url, status_filter) do
    alias GscAnalytics.Schemas.Performance
    alias GscAnalytics.Repo
    import Ecto.Query

    base_query =
      from(p in Performance,
        where: p.account_id == ^account_id,
        where: not is_nil(p.http_status),
        where: not is_nil(p.http_checked_at),
        order_by: [desc: p.http_checked_at],
        limit: 100,
        select: %{
          url: p.url,
          http_status: p.http_status,
          http_checked_at: p.http_checked_at
        }
      )
      |> maybe_filter_property(property_url)

    query =
      case status_filter do
        "all" ->
          base_query
          |> where([p], p.http_status >= 300)

        "3xx" ->
          base_query
          |> where([p], p.http_status >= 300 and p.http_status < 400)

        "4xx" ->
          base_query
          |> where([p], p.http_status >= 400 and p.http_status < 500)

        "5xx" ->
          base_query
          |> where([p], p.http_status >= 500)

        _ ->
          base_query
          |> where([p], p.http_status >= 300)
      end

    Repo.all(query)
  end

  defp fetch_global_stats(nil, _property_url) do
    %{
      total_checked: 0,
      status_2xx: 0,
      status_3xx: 0,
      status_4xx: 0,
      status_5xx: 0,
      unchecked: 0,
      percent_2xx: 0.0,
      percent_3xx: 0.0,
      percent_4xx: 0.0,
      percent_5xx: 0.0
    }
  end

  defp fetch_global_stats(account_id, property_url) do
    alias GscAnalytics.Schemas.Performance
    alias GscAnalytics.Repo
    import Ecto.Query

    # Optimized: Fetch all stats in a single query using COUNT(*) FILTER for both checked and unchecked
    stats =
      from(p in Performance,
        where: p.account_id == ^account_id,
        select: %{
          status_2xx:
            fragment("COUNT(*) FILTER (WHERE ? >= 200 AND ? < 300)", p.http_status, p.http_status),
          status_3xx:
            fragment("COUNT(*) FILTER (WHERE ? >= 300 AND ? < 400)", p.http_status, p.http_status),
          status_4xx:
            fragment("COUNT(*) FILTER (WHERE ? >= 400 AND ? < 500)", p.http_status, p.http_status),
          status_5xx: fragment("COUNT(*) FILTER (WHERE ? >= 500)", p.http_status),
          unchecked: fragment("COUNT(*) FILTER (WHERE ? IS NULL)", p.http_status),
          total_checked: fragment("COUNT(*) FILTER (WHERE ? IS NOT NULL)", p.http_status)
        }
      )
      |> maybe_filter_property(property_url)
      |> Repo.one()

    total_checked = stats.total_checked
    status_2xx = stats.status_2xx
    status_3xx = stats.status_3xx
    status_4xx = stats.status_4xx
    status_5xx = stats.status_5xx
    unchecked_count = stats.unchecked

    # Calculate percentages (avoid division by zero)
    percent_2xx =
      if total_checked > 0, do: Float.round(status_2xx / total_checked * 100, 1), else: 0.0

    percent_3xx =
      if total_checked > 0, do: Float.round(status_3xx / total_checked * 100, 1), else: 0.0

    percent_4xx =
      if total_checked > 0, do: Float.round(status_4xx / total_checked * 100, 1), else: 0.0

    percent_5xx =
      if total_checked > 0, do: Float.round(status_5xx / total_checked * 100, 1), else: 0.0

    %{
      total_checked: total_checked,
      status_2xx: status_2xx,
      status_3xx: status_3xx,
      status_4xx: status_4xx,
      status_5xx: status_5xx,
      unchecked: unchecked_count,
      percent_2xx: percent_2xx,
      percent_3xx: percent_3xx,
      percent_4xx: percent_4xx,
      percent_5xx: percent_5xx
    }
  end

  defp maybe_filter_property(query, nil), do: query

  defp maybe_filter_property(query, property_url) when is_binary(property_url) do
    where(query, [p], p.property_url == ^property_url)
  end

  defp scoped_job_for_selection(job, account_id, property_id) do
    if job_matches_scope?(job, account_id, property_id), do: job, else: nil
  end

  defp filter_history_for_scope(history, account_id, property_id)
       when is_list(history) and not is_nil(account_id) do
    Enum.filter(history, &job_matches_scope?(&1, account_id, property_id))
  end

  defp filter_history_for_scope(_history, _account_id, _property_id), do: []

  defp job_matches_scope?(nil, _account_id, _property_id), do: false
  defp job_matches_scope?(_job, nil, _property_id), do: false

  defp job_matches_scope?(job, account_id, property_id) do
    metadata = Map.get(job, :metadata, %{})
    account_match? = account_matches?(metadata, account_id)
    property_match? = property_matches?(metadata, property_id)

    account_match? and property_match?
  end

  defp account_matches?(metadata, account_id) do
    job_account_id = Map.get(metadata, :account_id)

    cond do
      is_nil(account_id) -> false
      is_nil(job_account_id) -> false
      true -> job_account_id == account_id
    end
  end

  defp property_matches?(metadata, property_id) do
    job_property_id = Map.get(metadata, :property_id)

    cond do
      is_nil(property_id) -> is_nil(job_property_id)
      is_nil(job_property_id) -> false
      true -> job_property_id == property_id
    end
  end

  # ============================================================================
  # Background HTTP Check Observability
  # ============================================================================

  @doc false
  def handle_telemetry(_event, _measurements, _metadata, socket_id) do
    # Send message to LiveView process to update queue stats
    send(self(), {:telemetry_update, socket_id})
  end

  defp get_queue_stats do
    import Ecto.Query

    # Query Oban jobs table for http_checks queue
    http_checks_query =
      from j in Oban.Job,
        where: j.queue == "http_checks" and j.state in ["available", "scheduled", "executing"],
        select: %{
          state: j.state,
          count: count(j.id)
        },
        group_by: j.state

    stats =
      try do
        GscAnalytics.Repo.all(http_checks_query)
        |> Enum.reduce(%{queued: 0, executing: 0, scheduled: 0}, fn stat, acc ->
          state_key =
            case stat.state do
              "available" -> :queued
              "executing" -> :executing
              "scheduled" -> :scheduled
              _ -> :other
            end

          Map.put(acc, state_key, stat.count)
        end)
      rescue
        _ -> %{queued: 0, executing: 0, scheduled: 0}
      end

    # Get most recent completed check
    last_check =
      try do
        from(j in Oban.Job,
          where: j.queue == "http_checks" and j.state == "completed",
          order_by: [desc: j.completed_at],
          limit: 1,
          select: j.completed_at
        )
        |> GscAnalytics.Repo.one()
      rescue
        _ -> nil
      end

    Map.put(stats, :last_completed_at, last_check)
  end
end
