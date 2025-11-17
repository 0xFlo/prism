defmodule GscAnalyticsWeb.DashboardSyncLive do
  use GscAnalyticsWeb, :live_view

  import GscAnalyticsWeb.Components.DashboardControls, only: [property_selector: 1]

  import GscAnalyticsWeb.Dashboard.HTMLHelpers,
    only: [format_date: 1, format_number: 1]

  import GscAnalyticsWeb.Live.DashboardSync,
    only: [
      progress_caption: 1,
      progress_failure_date: 1,
      progress_failure_raw_message: 1,
      status_badge: 1,
      format_timestamp: 1,
      sync_button_icon_class: 1,
      format_duration: 1,
      truncate_error: 2,
      rows_phrase: 1,
      query_sub_request_phrase: 1,
      http_batch_phrase: 1,
      url_phrase: 1,
      api_call_phrase: 1,
      format_date_safe: 1
    ]

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.DataSources.GSC.Support.{DeadLetter, SyncProgress}
  alias GscAnalyticsWeb.Live.{AccountHelpers, DashboardSync, DashboardSyncHelpers}
  alias GscAnalyticsWeb.PropertyRoutes

  @max_days 540
  @default_days "30"
  @telemetry_events [[:gsc_analytics, :url_pipeline, :message], [:gsc_analytics, :query_batch]]
  @telemetry_status_event [:gsc_analytics, :query_pipeline, :status]
  @telemetry_handler_events @telemetry_events ++ [@telemetry_status_event]
  @telemetry_history_limit 10
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
    progress_state = SyncProgress.current_state()

    {socket, account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, params)

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
      socket =
        socket
        |> assign(:page_title, "Sync Status")
        |> assign(:day_options, @day_options)
        |> assign(:form, DashboardSync.build_form(@default_days))
        |> assign(:sync_info, DashboardSync.empty_sync_info())
        |> assign(:sync_info_status, :idle)
        |> assign(:sync_info_requested_account_id, nil)
        |> assign(:sync_info_loaded_account_id, nil)
        |> assign(:sync_info_loaded_property_id, nil)
        |> assign(:telemetry_events, [])
        |> assign(:telemetry_counters, new_telemetry_counters())
        |> assign(:pipeline_stats, new_pipeline_stats())
        |> assign(:dead_letters, DeadLetter.all())
        |> assign(:telemetry_handler_id, nil)
        |> DashboardSyncHelpers.assign_progress(progress_state)

      socket =
        if connected?(socket) do
          SyncProgress.subscribe()
          handler_id = attach_telemetry_handler()
          assign(socket, :telemetry_handler_id, handler_id)
        else
          socket
        end

      property = socket.assigns.current_property
      property_url = property && property.property_url

      property_label =
        property &&
          (property.display_name || AccountHelpers.display_property_label(property.property_url))

      property_favicon_url = property && property.favicon_url

      socket =
        socket
        |> assign(:property_label, property_label)
        |> assign(:property_favicon_url, property_favicon_url)
        |> DashboardSyncHelpers.maybe_request_sync_info(account.id, property_url, force: true)

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    previous_property_id = socket.assigns[:current_property_id]

    current_path = URI.parse(uri).path || "/dashboard/sync"

    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params)
      |> assign(:current_path, current_path)

    account_id = socket.assigns.current_account_id
    new_property_id = socket.assigns[:current_property_id]
    property = socket.assigns.current_property
    property_url = property && property.property_url

    property_label =
      property &&
        (property.display_name || AccountHelpers.display_property_label(property.property_url))

    property_favicon_url = property && property.favicon_url

    # Clear progress when property changes
    socket =
      if previous_property_id != new_property_id do
        DashboardSyncHelpers.assign_progress(socket, nil)
      else
        socket
      end

    # Force reload if account or property changed
    force? =
      socket.assigns[:sync_info_loaded_account_id] != account_id or
        socket.assigns[:sync_info_loaded_property_id] != new_property_id

    socket =
      socket
      |> assign(:property_label, property_label)
      |> assign(:property_favicon_url, property_favicon_url)
      |> DashboardSyncHelpers.maybe_request_sync_info(account_id, property_url, force: force?)

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, %{assigns: %{telemetry_handler_id: handler_id}}) do
    if handler_id, do: :telemetry.detach(handler_id)
    :ok
  end

  @impl true
  def handle_event("start_sync", %{"sync" => params}, %{assigns: assigns} = socket) do
    case DashboardSync.parse_days(params, @max_days) do
      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}

      {:ok, :full_history} ->
        if assigns.progress.active? do
          {:noreply, put_flash(socket, :error, "A sync is already in progress")}
        else
          account_id = socket.assigns.current_account_id

          case DashboardSync.configured_site(socket.assigns.current_property) do
            {:ok, site_url} ->
              Task.start(fn -> Sync.sync_full_history(site_url, account_id: account_id) end)

              form = DashboardSync.build_form("full")

              property_name =
                socket.assigns.current_property.display_name ||
                  socket.assigns.current_property.property_url

              {:noreply,
               socket
               |> assign(:form, form)
               |> put_flash(:info, "Full history sync started for #{property_name}")}

            {:error, message} ->
              {:noreply, put_flash(socket, :error, message)}
          end
        end

      {:ok, days} when is_integer(days) ->
        if assigns.progress.active? do
          {:noreply, put_flash(socket, :error, "A sync is already in progress")}
        else
          account_id = socket.assigns.current_account_id

          case DashboardSync.configured_site(socket.assigns.current_property) do
            {:ok, site_url} ->
              Task.start(fn -> Sync.sync_last_n_days(site_url, days, account_id: account_id) end)

              form = DashboardSync.build_form(Integer.to_string(days))

              property_name =
                socket.assigns.current_property.display_name ||
                  socket.assigns.current_property.property_url

              {:noreply,
               socket
               |> assign(:form, form)
               |> put_flash(:info, "Sync started for #{property_name}: last #{days} days")}

            {:error, message} ->
              {:noreply, put_flash(socket, :error, message)}
          end
        end
    end
  end

  @impl true
  def handle_event("start_sync", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_account", %{"account_id" => account_id}, socket) do
    {:noreply,
     push_patch(
       socket,
       to: PropertyRoutes.sync_path(socket.assigns.current_property_id, %{account_id: account_id})
     )}
  end

  @impl true
  def handle_event("switch_property", %{"property_id" => property_id}, socket) do
    {:noreply, push_patch(socket, to: PropertyRoutes.sync_path(property_id))}
  end

  @impl true
  def handle_event("clear_dead_letters", _params, socket) do
    DeadLetter.clear()
    {:noreply, assign(socket, :dead_letters, [])}
  end

  @impl true
  def handle_event("retry_failed_day", %{"date" => date_str}, %{assigns: assigns} = socket) do
    with true <- is_integer(assigns.current_account_id),
         {:ok, date} <- Date.from_iso8601(date_str) do
      cond do
        assigns.progress.active? ->
          {:noreply, put_flash(socket, :error, "A sync is already in progress")}

        true ->
          account_id = assigns.current_account_id

          case DashboardSync.configured_site(assigns.current_property) do
            {:ok, site_url} ->
              Task.start(fn ->
                Sync.sync_date_range(site_url, date, date,
                  account_id: account_id,
                  force?: true,
                  stop_on_empty?: false
                )
              end)

              {:noreply,
               socket
               |> put_flash(:info, "Retrying sync for #{format_date(date)}")
               |> DashboardSyncHelpers.maybe_request_sync_info(account_id, site_url, force: true)}

            {:error, message} ->
              {:noreply, put_flash(socket, :error, message)}
          end
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Invalid failure date")}
    end
  end

  @impl true
  def handle_event("pause_sync", _params, %{assigns: %{progress: progress}} = socket) do
    DashboardSync.maybe_apply_control(progress, :pause)
    {:noreply, socket}
  end

  @impl true
  def handle_event("resume_sync", _params, %{assigns: %{progress: progress}} = socket) do
    DashboardSync.maybe_apply_control(progress, :resume)
    {:noreply, socket}
  end

  @impl true
  def handle_event("stop_sync", _params, %{assigns: %{progress: progress}} = socket) do
    DashboardSync.maybe_apply_control(progress, :stop)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_progress, %{job: job} = payload}, socket) do
    socket = DashboardSyncHelpers.assign_progress(socket, job)

    socket =
      case payload.type do
        :finished ->
          property_url =
            socket.assigns.current_property && socket.assigns.current_property.property_url

          DashboardSyncHelpers.maybe_request_sync_info(
            socket,
            socket.assigns.current_account_id,
            property_url,
            force: true
          )

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info(
        {:load_sync_info, account_id, property_url, force?},
        %{assigns: assigns} = socket
      ) do
    cond do
      assigns.current_account_id != account_id and not force? ->
        {:noreply, socket}

      true ->
        info = DashboardSync.load_sync_info(assigns.current_scope, account_id, property_url)

        socket =
          if assigns.current_account_id == account_id do
            property_id = assigns.current_property && assigns.current_property.id
            DashboardSyncHelpers.assign_sync_info(socket, info, account_id, property_id)
          else
            socket
          end

        {:noreply, socket}
    end
  end

  def handle_info({:telemetry_event, event, measurements, metadata}, socket)
      when event in @telemetry_events do
    entry = build_telemetry_entry(event, measurements, metadata)

    socket =
      socket
      |> update(:telemetry_events, fn events ->
        [entry | events]
        |> Enum.take(@telemetry_history_limit)
      end)
      |> assign(:telemetry_counters, update_counters(socket.assigns.telemetry_counters, entry))
      |> assign(:dead_letters, DeadLetter.all())

    {:noreply, socket}
  end

  def handle_info({:telemetry_event, event, measurements, metadata}, socket)
      when event == @telemetry_status_event do
    stats = update_pipeline_stats(socket.assigns.pipeline_stats, measurements, metadata)
    {:noreply, assign(socket, :pipeline_stats, stats)}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  def handle_telemetry(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp attach_telemetry_handler do
    handler_id = "dashboard-sync-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      @telemetry_handler_events,
      &__MODULE__.handle_telemetry/4,
      self()
    )

    handler_id
  end

  defp build_telemetry_entry(event, measurements, metadata) do
    %{
      event: event,
      status: metadata[:status] || :ok,
      date: metadata[:date],
      site_url: metadata[:site_url],
      duration_ms: measurements[:duration_ms],
      batch_size: measurements[:batch_size],
      recorded_at: DateTime.utc_now()
    }
  end

  defp telemetry_badge(:ok), do: {"Completed", "badge badge-success badge-sm"}
  defp telemetry_badge(:skipped), do: {"Skipped", "badge badge-neutral badge-sm"}

  defp telemetry_badge({:error, _reason}),
    do: {"Error", "badge badge-error badge-sm"}

  defp telemetry_badge(_status), do: {"Info", "badge badge-ghost badge-sm"}

  defp telemetry_label([:gsc_analytics, :url_pipeline, :message]), do: "URL stage"
  defp telemetry_label([:gsc_analytics, :query_batch]), do: "Query batch"
  defp telemetry_label(_), do: "Pipeline"

  defp telemetry_status_text({:error, reason}), do: "Error: #{inspect(reason)}"

  defp telemetry_status_text(status) when is_atom(status),
    do: Phoenix.Naming.humanize("#{status}")

  defp telemetry_status_text(_), do: "Info"

  defp new_pipeline_stats do
    %{
      query: %{
        status: :idle,
        queue_depth: 0,
        in_flight: 0,
        writer_backlog: false,
        reason: nil,
        site_url: nil,
        updated_at: nil
      }
    }
  end

  defp update_pipeline_stats(stats, _measurements, metadata) do
    query_stats =
      stats.query
      |> Map.merge(%{
        status: metadata[:status] || stats.query.status,
        queue_depth: metadata[:queue_depth] || stats.query.queue_depth,
        in_flight: metadata[:in_flight] || stats.query.in_flight,
        writer_backlog: metadata[:writer_backlog] || false,
        reason: metadata[:reason],
        site_url: metadata[:site_url] || stats.query.site_url,
        updated_at: DateTime.utc_now()
      })

    Map.put(stats, :query, query_stats)
  end

  defp pipeline_status_badge(%{status: :dispatch}), do: {"Active", "badge badge-success badge-sm"}

  defp pipeline_status_badge(%{status: :backpressure}),
    do: {"Backpressure", "badge badge-warning badge-sm"}

  defp pipeline_status_badge(%{status: :halted}), do: {"Halted", "badge badge-error badge-sm"}
  defp pipeline_status_badge(%{status: :error}), do: {"Error", "badge badge-error badge-sm"}

  defp pipeline_status_badge(%{status: :finalizing}),
    do: {"Finalizing", "badge badge-info badge-sm"}

  defp pipeline_status_badge(%{status: :idle}), do: {"Idle", "badge badge-ghost badge-sm"}
  defp pipeline_status_badge(_), do: {"Updating", "badge badge-ghost badge-sm"}

  defp pipeline_status_label(%{status: :dispatch}), do: "Dispatching query batches"
  defp pipeline_status_label(%{status: :backpressure}), do: "Backpressure detected"
  defp pipeline_status_label(%{status: :halted}), do: "Pipeline halted"
  defp pipeline_status_label(%{status: :error}), do: "Pipeline error"
  defp pipeline_status_label(%{status: :finalizing}), do: "Flushing pending writers"
  defp pipeline_status_label(%{status: :pending}), do: "Waiting for results"
  defp pipeline_status_label(%{status: :idle}), do: "Idle"
  defp pipeline_status_label(_), do: "Updating"

  defp pipeline_status_detail(%{status: :backpressure, reason: reason}) do
    case reason do
      :writer_backlog -> "Writer backlog detected. Waiting for database writes to finish."
      :max_in_flight -> "All pagination slots are in use."
      :max_queue_size -> "Coordinator queue is at capacity."
      other -> "Backpressure reason: #{inspect(other)}"
    end
  end

  defp pipeline_status_detail(%{status: :dispatch, queue_depth: depth, in_flight: in_flight}) do
    "Dispatching work: #{depth} queued page(s), #{in_flight} in flight."
  end

  defp pipeline_status_detail(%{status: :finalizing}),
    do: "Waiting for final query writers to complete."

  defp pipeline_status_detail(%{status: :halted}),
    do: "Pipeline halted. See retry queue for details."

  defp pipeline_status_detail(%{status: :error, reason: reason}), do: "Error: #{inspect(reason)}"
  defp pipeline_status_detail(_), do: "Monitoring pipeline health."

  defp pipeline_writer_backlog_label(%{writer_backlog: true}), do: "Yes"
  defp pipeline_writer_backlog_label(_), do: "No"

  defp format_pipeline_duration_ms(value) when is_integer(value) or is_float(value) do
    ms =
      value
      |> Kernel.*(1.0)
      |> Float.round(2)

    "#{ms} ms"
  end

  defp format_pipeline_duration_ms(_), do: "—"

  defp new_telemetry_counters do
    %{
      url: %{ok: 0, error: 0, skipped: 0},
      query: %{ok: 0, error: 0, skipped: 0}
    }
  end

  defp update_counters(counters, entry) do
    {key, status_key} = telemetry_counter_keys(entry)
    update_in(counters, [key, status_key], fn value -> (value || 0) + 1 end)
  end

  defp telemetry_counter_keys(entry) do
    key =
      case entry.event do
        [:gsc_analytics, :url_pipeline, :message] -> :url
        [:gsc_analytics, :query_batch] -> :query
        _ -> :url
      end

    status_key =
      case entry.status do
        {:error, _reason} -> :error
        :skipped -> :skipped
        _ -> :ok
      end

    {key, status_key}
  end

  defp telemetry_counter_label(:url), do: "URL pipeline"
  defp telemetry_counter_label(:query), do: "Query pipeline"
  defp telemetry_counter_label(_), do: "Pipeline"
end
