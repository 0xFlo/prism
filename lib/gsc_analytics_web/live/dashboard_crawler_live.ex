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

  import GscAnalyticsWeb.Components.DashboardControls, only: [property_selector: 1]

  import GscAnalyticsWeb.Dashboard.Formatters

  alias GscAnalytics.Crawler
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.Live.PaginationHelpers
  alias GscAnalyticsWeb.PropertyRoutes

  @filter_options [
    {"Stale URLs (unchecked or >7 days old)", "stale"},
    {"All URLs", "all"},
    {"Broken Links (4xx/5xx)", "broken"},
    {"Redirected URLs (3xx)", "redirected"}
  ]

  @filter_label_lookup Map.new(@filter_options, fn {label, value} -> {value, label} end)

  @impl true
  def mount(params, _session, socket) do
    # LiveView best practice: Subscribe to PubSub only on connected socket
    if connected?(socket) do
      Crawler.subscribe()
      # Subscribe to telemetry for background HTTP check updates
      :ok =
        :telemetry.attach(
          "dashboard-http-checks-#{inspect(self())}",
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

      # Initialize with default pagination values
      {problem_urls, total_count} =
        fetch_problem_urls_paginated(account.id, property_url, "all", 1, 25)

      total_pages = PaginationHelpers.calculate_total_pages(total_count, 25)
      global_stats = fetch_global_stats(account.id, property_url)
      property_id = property && property.id
      scoped_job = scoped_job_for_selection(current_job, account.id, property_id)
      history_for_scope = filter_history_for_scope(history, account.id, property_id)

      socket =
        socket
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
        |> assign(:problem_page, 1)
        |> assign(:problem_limit, 25)
        |> assign(:problem_total_pages, total_pages)
        |> assign(:problem_total_count, total_count)
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

    # Parse pagination params from URL
    page = PaginationHelpers.parse_page(params["problem_page"])
    limit = PaginationHelpers.parse_limit(params["problem_limit"])

    # Fetch paginated problem URLs and total count
    {problem_urls, total_count} =
      fetch_problem_urls_paginated(
        account_id,
        property_url,
        socket.assigns.selected_status_filter,
        page,
        limit
      )

    total_pages = PaginationHelpers.calculate_total_pages(total_count, limit)

    socket =
      socket
      |> assign(:problem_urls, problem_urls)
      |> assign(:problem_page, page)
      |> assign(:problem_limit, limit)
      |> assign(:problem_total_pages, total_pages)
      |> assign(:problem_total_count, total_count)
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
    # Reset pagination to page 1 when changing filters
    params = %{
      problem_page: 1,
      problem_limit: socket.assigns.problem_limit
    }

    {:noreply,
     socket
     |> assign(:selected_status_filter, status)
     |> push_crawler_patch(params)}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    {:noreply,
     push_patch(
       socket,
       to:
         PropertyRoutes.crawler_path(socket.assigns.current_property_id, %{account_id: account_id})
     )}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    {:noreply, push_patch(socket, to: PropertyRoutes.crawler_path(property_id))}
  end

  def handle_event("switch_property", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("next_page", _, socket) do
    next_page = min(socket.assigns.problem_page + 1, socket.assigns.problem_total_pages)

    params = %{
      problem_page: next_page,
      problem_limit: socket.assigns.problem_limit
    }

    {:noreply, push_crawler_patch(socket, params)}
  end

  @impl true
  def handle_event("prev_page", _, socket) do
    prev_page = max(socket.assigns.problem_page - 1, 1)

    params = %{
      problem_page: prev_page,
      problem_limit: socket.assigns.problem_limit
    }

    {:noreply, push_crawler_patch(socket, params)}
  end

  @impl true
  def handle_event("goto_page", %{"page" => page_str}, socket) do
    page = String.to_integer(page_str)
    clamped_page = max(1, min(page, socket.assigns.problem_total_pages))

    params = %{
      problem_page: clamped_page,
      problem_limit: socket.assigns.problem_limit
    }

    {:noreply, push_crawler_patch(socket, params)}
  end

  @impl true
  def handle_event("change_limit", %{"limit" => limit_str}, socket) do
    limit = String.to_integer(limit_str)

    params = %{
      problem_page: 1,
      problem_limit: limit
    }

    {:noreply, push_crawler_patch(socket, params)}
  end

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

      # Reload problem URLs with current pagination state
      {problem_urls, total_count} =
        fetch_problem_urls_paginated(
          account_id,
          property_url,
          socket.assigns.selected_status_filter,
          socket.assigns.problem_page,
          socket.assigns.problem_limit
        )

      total_pages =
        PaginationHelpers.calculate_total_pages(total_count, socket.assigns.problem_limit)

      # Refresh global stats to reflect latest database state
      global_stats = fetch_global_stats(account_id, property_url)

      socket =
        socket
        |> assign_progress(job)
        |> assign(:history, history)
        |> assign(:problem_urls, problem_urls)
        |> assign(:problem_total_count, total_count)
        |> assign(:problem_total_pages, total_pages)
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

  @impl true
  def terminate(_reason, _socket) do
    # Detach telemetry handler to prevent memory leaks
    :telemetry.detach("dashboard-http-checks-#{inspect(self())}")
    :ok
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp assign_progress(socket, nil) do
    status_counts = default_status_counts()

    assign(socket, :progress, %{
      job_id: nil,
      running?: false,
      total_urls: 0,
      checked: 0,
      checked_urls: 0,
      percent: 0.0,
      rate: nil,
      crawl_speed: nil,
      started_at: nil,
      finished_at: nil,
      duration_ms: nil,
      status_counts: status_counts,
      status_2xx: Map.get(status_counts, "2xx"),
      status_3xx: Map.get(status_counts, "3xx"),
      status_4xx: Map.get(status_counts, "4xx"),
      status_5xx: Map.get(status_counts, "5xx"),
      errors: Map.get(status_counts, "errors"),
      filter: nil
    })
  end

  defp assign_progress(socket, job) do
    total = job.total_urls || 0
    checked = job.checked || 0
    running? = is_nil(Map.get(job, :finished_at))
    duration_ms = calculate_duration_for_progress(job, running?)

    percent =
      if total > 0 do
        min(checked / total * 100, 100.0) |> Float.round(2)
      else
        0.0
      end

    # Calculate crawl speed (URLs per second)
    rate = calculate_crawl_rate(job, checked, running?)
    status_counts = job.status_counts || default_status_counts()
    filter = Map.get(job, :filter) || get_in(job, [:metadata, :filter])
    checked_urls = Map.get(job, :checked_urls, checked)

    assign(socket, :progress, %{
      job_id: job.id,
      running?: running?,
      total_urls: total,
      checked: checked,
      checked_urls: checked_urls,
      percent: percent,
      rate: rate,
      crawl_speed: rate,
      started_at: job.started_at,
      finished_at: Map.get(job, :finished_at),
      duration_ms: duration_ms,
      status_counts: status_counts,
      status_2xx: Map.get(status_counts, "2xx", 0),
      status_3xx: Map.get(status_counts, "3xx", 0),
      status_4xx: Map.get(status_counts, "4xx", 0),
      status_5xx: Map.get(status_counts, "5xx", 0),
      errors: Map.get(status_counts, "errors", 0),
      filter: filter
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

  defp calculate_duration_for_progress(job, true) do
    DateTime.diff(DateTime.utc_now(), job.started_at, :millisecond)
  end

  defp calculate_duration_for_progress(job, false) do
    Map.get(job, :duration_ms)
  end

  defp default_status_counts do
    %{
      "2xx" => 0,
      "3xx" => 0,
      "4xx" => 0,
      "5xx" => 0,
      "errors" => 0
    }
  end

  defp property_context(nil) do
    %{
      label: nil,
      favicon_url: nil,
      url: nil
    }
  end

  defp property_context(property) when is_map(property) do
    property_url = Map.get(property, :property_url)

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
      favicon_url: Map.get(property, :favicon_url),
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

  # Formatting helpers moved to GscAnalyticsWeb.Dashboard.Formatters module

  defp fetch_problem_urls_paginated(nil, _property_url, _status_filter, _page, _limit),
    do: {[], 0}

  defp fetch_problem_urls_paginated(account_id, property_url, status_filter, page, limit) do
    alias GscAnalytics.Schemas.Performance
    alias GscAnalytics.Repo
    import Ecto.Query

    # Build base query with common filters
    base_query =
      from(p in Performance,
        where: p.account_id == ^account_id,
        where: not is_nil(p.http_status),
        where: not is_nil(p.http_checked_at)
      )
      |> maybe_filter_property(property_url)

    # Apply status filter
    filtered_query =
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

    # Get total count for pagination
    total_count = Repo.aggregate(filtered_query, :count, :id)

    # Calculate offset
    offset = (page - 1) * limit

    # Fetch paginated results
    results =
      filtered_query
      |> order_by([p], desc: p.http_checked_at)
      |> limit(^limit)
      |> offset(^offset)
      |> select([p], %{
        id: p.id,
        url: p.url,
        http_status: p.http_status,
        http_checked_at: p.http_checked_at,
        redirect_url: p.redirect_url,
        http_redirect_chain: p.http_redirect_chain
      })
      |> Repo.all()

    {results, total_count}
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
  # Pagination Helpers - Moved to PaginationHelpers module
  # ============================================================================

  defp push_crawler_patch(socket, params) do
    # Merge pagination params with current account/property params
    current_params = %{
      account_id: socket.assigns.current_account_id,
      property_id: socket.assigns.current_property_id
    }

    merged_params = Map.merge(current_params, params)

    push_patch(
      socket,
      to: PropertyRoutes.crawler_path(socket.assigns.current_property_id, merged_params)
    )
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

  # ============================================================================
  # Mission Impossible Theme Helper Functions
  # ============================================================================

  defp history_status(check) do
    status =
      Map.get(check, :status) ||
        Map.get(check, "status") ||
        get_in(check, [:metadata, :status])

    cond do
      is_binary(status) -> String.downcase(status)
      is_atom(status) -> status |> Atom.to_string() |> String.downcase()
      true -> "completed"
    end
  end

  defp history_status_class("completed"), do: "mi-status-active"
  defp history_status_class("failed"), do: "mi-status-critical"
  defp history_status_class("running"), do: "mi-status-warning"
  defp history_status_class(_), do: nil

  defp history_checked_count(check) do
    Map.get(check, :checked_urls) ||
      Map.get(check, "checked_urls") ||
      Map.get(check, :checked) ||
      Map.get(check, "checked") ||
      0
  end

  defp history_filter_label(check) do
    filter =
      Map.get(check, :filter) ||
        Map.get(check, "filter") ||
        get_in(check, [:metadata, :filter]) ||
        get_in(check, ["metadata", "filter"])

    filter_label_for_value(filter)
  end

  defp filter_label_for_value(nil), do: nil

  defp filter_label_for_value(filter) when is_atom(filter) do
    filter
    |> Atom.to_string()
    |> filter_label_for_value()
  end

  defp filter_label_for_value(filter) when is_binary(filter) do
    Map.get(@filter_label_lookup, filter, filter)
  end

  defp filter_label_for_value(_), do: nil

  def redirect_destination(url_info) when is_map(url_info) do
    redirect_url =
      url_info
      |> Map.get(:redirect_url)
      |> presence_or_nil()

    cond do
      redirect_url ->
        redirect_url

      true ->
        url_info
        |> Map.get(:http_redirect_chain)
        |> final_redirect_from_chain()
    end
  end

  def redirect_destination(_), do: nil

  def redirecting?(url_info) when is_map(url_info) do
    status = Map.get(url_info, :http_status)
    destination = redirect_destination(url_info)
    status && status >= 300 && status < 400 && not is_nil(destination)
  end

  def redirecting?(_), do: false

  def truncate_url(url, max_length \\ 80)

  def truncate_url(url, max_length)
      when is_binary(url) and is_integer(max_length) and max_length > 0 do
    if String.length(url) <= max_length do
      url
    else
      String.slice(url, 0, max_length) <> "…"
    end
  end

  def truncate_url(_url, _max_length), do: nil

  def status_color_class(status) when is_integer(status) do
    cond do
      status >= 200 and status < 300 -> "mi-status-active"
      status >= 300 and status < 400 -> "mi-status-warning"
      status >= 400 -> "mi-status-critical"
      true -> "mi-terminal-text"
    end
  end

  def status_color_class(_), do: "mi-terminal-text"

  defp presence_or_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence_or_nil(_), do: nil

  defp final_redirect_from_chain(%{} = chain) when map_size(chain) > 0 do
    chain
    |> Enum.map(fn {step, target} -> {parse_step_index(step), presence_or_nil(target)} end)
    |> Enum.reject(fn {_idx, target} -> is_nil(target) end)
    |> Enum.sort_by(&elem(&1, 0))
    |> List.last()
    |> case do
      {_, target} -> target
      _ -> nil
    end
  end

  defp final_redirect_from_chain(_), do: nil

  defp parse_step_index("step_" <> index) do
    case Integer.parse(index) do
      {value, _} -> value
      :error -> 0
    end
  end

  defp parse_step_index(_), do: 0
end
