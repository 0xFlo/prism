defmodule GscAnalyticsWeb.DashboardWorkflowsLive do
  @moduledoc """
  LiveView for workflow execution and real-time progress monitoring.

  Features:
  - List available workflows
  - Execute workflows with real-time progress updates
  - Monitor active executions
  - View execution history and events
  """

  use GscAnalyticsWeb, :live_view

  import Ecto.Query

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Workflow
  alias GscAnalytics.Workflows.{Engine, Execution, ExecutionEvent, ProgressTracker}
  alias GscAnalyticsWeb.Live.AccountHelpers

  @impl true
  def mount(params, _session, socket) do
    # Subscribe to workflow progress updates and workflow changes
    if connected?(socket) do
      ProgressTracker.subscribe()
      GscAnalytics.Workflows.subscribe()
    end

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
      workflows = list_workflows(account.id)
      active_executions = list_active_executions(account.id)
      recent_executions = list_recent_executions(account.id, limit: 10)

      socket =
        socket
        |> assign(:current_path, "/dashboard/workflows")
        |> assign(:page_title, "Workflow Runner")
        |> assign(:workflows, workflows)
        |> assign(:active_executions, active_executions)
        |> assign(:recent_executions, recent_executions)
        |> assign(:selected_execution_id, nil)
        |> assign(:execution_events, [])

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

    # Reload data when account changes
    workflows = list_workflows(account_id)
    active_executions = list_active_executions(account_id)
    recent_executions = list_recent_executions(account_id, limit: 10)

    socket =
      socket
      |> assign(:workflows, workflows)
      |> assign(:active_executions, active_executions)
      |> assign(:recent_executions, recent_executions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("run_workflow", %{"id" => workflow_id}, socket) do
    account_id = socket.assigns.current_account_id

    case get_workflow(workflow_id, account_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Workflow not found")}

      workflow ->
        # Create execution record
        {:ok, execution} =
          %Execution{}
          |> Execution.changeset(%{
            workflow_id: workflow.id,
            account_id: account_id,
            input_data: %{}
          })
          |> Repo.insert()

        # Start execution engine
        case Engine.start_execution(execution.id) do
          {:ok, _pid} ->
            # Trigger execution
            Engine.execute(execution.id)

            # Reload active executions
            active_executions = list_active_executions(account_id)

            socket =
              socket
              |> assign(:active_executions, active_executions)
              |> assign(:selected_execution_id, execution.id)
              |> put_flash(:info, "Started workflow: #{workflow.name}")

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("view_execution", %{"id" => execution_id}, socket) do
    events = list_execution_events(execution_id)

    socket =
      socket
      |> assign(:selected_execution_id, execution_id)
      |> assign(:execution_events, events)

    {:noreply, socket}
  end

  @impl true
  def handle_event("pause_execution", %{"id" => execution_id}, socket) do
    Engine.pause(execution_id)
    {:noreply, put_flash(socket, :info, "Paused execution")}
  end

  @impl true
  def handle_event("resume_execution", %{"id" => execution_id}, socket) do
    Engine.resume(execution_id)
    {:noreply, put_flash(socket, :info, "Resumed execution")}
  end

  @impl true
  def handle_event("cancel_execution", %{"id" => execution_id}, socket) do
    Engine.stop_execution(execution_id)
    {:noreply, put_flash(socket, :info, "Cancelled execution")}
  end

  @impl true
  def handle_info({:workflow_progress, event}, socket) do
    account_id = socket.assigns.current_account_id

    # Reload active executions to show updated progress
    active_executions = list_active_executions(account_id)
    recent_executions = list_recent_executions(account_id, limit: 10)

    # If viewing this execution's events, reload them
    execution_events =
      if socket.assigns.selected_execution_id == event.execution_id do
        list_execution_events(event.execution_id)
      else
        socket.assigns.execution_events
      end

    socket =
      socket
      |> assign(:active_executions, active_executions)
      |> assign(:recent_executions, recent_executions)
      |> assign(:execution_events, execution_events)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:workflow_event, %{workflow: _workflow, event: _event_type}}, socket) do
    account_id = socket.assigns.current_account_id

    # Reload workflows list when a workflow is created/updated/deleted
    workflows = list_workflows(account_id)

    socket = assign(socket, :workflows, workflows)

    {:noreply, socket}
  end

  ## Private Functions

  defp list_workflows(account_id) do
    Workflow
    |> where([w], w.account_id == ^account_id)
    |> where([w], w.status in [:published, :draft])
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  defp get_workflow(workflow_id, account_id) do
    Workflow
    |> where([w], w.id == ^workflow_id and w.account_id == ^account_id)
    |> Repo.one()
  end

  defp list_active_executions(account_id) do
    Execution
    |> where([e], e.account_id == ^account_id)
    |> where([e], e.status in [:queued, :running, :paused])
    |> order_by([e], desc: e.inserted_at)
    |> preload(:workflow)
    |> Repo.all()
  end

  defp list_recent_executions(account_id, opts) do
    limit = Keyword.get(opts, :limit, 10)

    Execution
    |> where([e], e.account_id == ^account_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> preload(:workflow)
    |> Repo.all()
  end

  defp list_execution_events(execution_id) do
    ExecutionEvent
    |> ExecutionEvent.for_execution(execution_id)
    |> ExecutionEvent.chronological()
    |> Repo.all()
  end

  defp status_badge_class(status) do
    case status do
      :queued -> "badge badge-ghost"
      :running -> "badge badge-info"
      :paused -> "badge badge-warning"
      :completed -> "badge badge-success"
      :failed -> "badge badge-error"
      :cancelled -> "badge badge-ghost"
      _ -> "badge"
    end
  end

  defp event_type_icon(event_type) do
    case event_type do
      :execution_started -> "hero-play"
      :execution_paused -> "hero-pause"
      :execution_resumed -> "hero-play"
      :execution_cancelled -> "hero-x-mark"
      :execution_finished -> "hero-check"
      :step_started -> "hero-arrow-right"
      :step_completed -> "hero-check-circle"
      :step_failed -> "hero-x-circle"
      :awaiting_review -> "hero-clock"
      _ -> "hero-information-circle"
    end
  end

  defp event_type_class(event_type) do
    case event_type do
      :execution_started -> "text-blue-600"
      :execution_paused -> "text-yellow-600"
      :execution_resumed -> "text-blue-600"
      :execution_cancelled -> "text-gray-600"
      :execution_finished -> "text-green-600"
      :step_started -> "text-blue-500"
      :step_completed -> "text-green-500"
      :step_failed -> "text-red-500"
      :awaiting_review -> "text-yellow-500"
      _ -> "text-gray-500"
    end
  end

  defp format_event_type(event_type) do
    event_type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
