defmodule GscAnalyticsWeb.DashboardSyncLive do
  use GscAnalyticsWeb, :live_view

  import GscAnalyticsWeb.Components.DashboardControls, only: [property_selector: 1]

  import GscAnalyticsWeb.Dashboard.HTMLHelpers,
    only: [format_date: 1, format_number: 1, days_ago: 1]

  import GscAnalyticsWeb.Live.DashboardSync,
    only: [
      progress_caption: 1,
      progress_failure_date: 1,
      progress_failure_raw_message: 1,
      status_badge: 1,
      format_timestamp: 1,
      event_marker_class: 1,
      event_badge_label: 1,
      event_tag_class: 1,
      sync_button_icon_class: 1,
      format_duration: 1,
      truncate_error: 2,
      rows_phrase: 1,
      query_batch_phrase: 1,
      query_sub_request_phrase: 1,
      http_batch_phrase: 1,
      url_phrase: 1,
      url_request_phrase: 1,
      api_call_phrase: 1,
      format_date_safe: 1
    ]

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalyticsWeb.Live.{AccountHelpers, DashboardSync, DashboardSyncHelpers}
  alias GscAnalyticsWeb.PropertyRoutes

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
        |> DashboardSyncHelpers.assign_progress(progress_state)

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

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}
end
