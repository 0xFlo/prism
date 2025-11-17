defmodule GscAnalyticsWeb.Live.DashboardSyncHelpers do
  @moduledoc """
  Convenience helpers that apply DashboardSync service data to LiveView sockets.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView
  alias GscAnalyticsWeb.Live.DashboardSync

  @doc """
  Normalize the current progress payload using the service and assign it.
  """
  def assign_progress(socket, job) do
    {status, progress} =
      DashboardSync.progress_from_job(
        job,
        socket.assigns[:current_account_id],
        socket.assigns[:current_property]
      )

    case status do
      :reset -> assign(socket, :progress, progress)
      :ok -> assign(socket, :progress, progress)
    end
  end

  @doc """
  Replace the progress assign with the blank template.
  """
  def reset_progress(socket) do
    assign(socket, :progress, DashboardSync.new_progress())
  end

  @doc """
  Kick off an async sync-info load unless we already have a request in-flight.
  """
  def maybe_request_sync_info(socket, account_id, property_url, opts \\ []) do
    force? = Keyword.get(opts, :force?, false)
    requested_account = socket.assigns[:sync_info_requested_account_id]
    loaded_account = socket.assigns[:sync_info_loaded_account_id]
    status = socket.assigns[:sync_info_status] || :idle

    cond do
      not LiveView.connected?(socket) ->
        socket

      not force? and loaded_account == account_id ->
        socket

      status == :loading and requested_account == account_id and not force? ->
        socket

      true ->
        send(self(), {:load_sync_info, account_id, property_url, force?})

        socket
        |> assign(:sync_info_status, :loading)
        |> assign(:sync_info_requested_account_id, account_id)
        |> maybe_reset_sync_info(loaded_account, account_id, force?)
    end
  end

  defp maybe_reset_sync_info(socket, _loaded_account, _account_id, true = _force?) do
    assign(socket, :sync_info, DashboardSync.empty_sync_info())
  end

  defp maybe_reset_sync_info(socket, loaded_account, account_id, _force?) do
    if loaded_account != account_id do
      assign(socket, :sync_info, DashboardSync.empty_sync_info())
    else
      socket
    end
  end

  @doc """
  Assign the loaded sync info metadata once fetched.
  """
  def assign_sync_info(socket, info, account_id, property_id) do
    socket
    |> assign(:sync_info, info)
    |> assign(:sync_info_status, :ready)
    |> assign(:sync_info_loaded_account_id, account_id)
    |> assign(:sync_info_loaded_property_id, property_id)
    |> assign(:sync_info_requested_account_id, nil)
  end
end
