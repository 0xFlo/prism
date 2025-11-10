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
  alias GscAnalytics.Workflows
  alias GscAnalytics.Workflows.{Engine, Execution, ExecutionEvent, ProgressTracker}
  alias GscAnalyticsWeb.Live.AccountHelpers
  alias GscAnalyticsWeb.PropertyRoutes

  @impl true
  def mount(params, _session, socket) do
    # Subscribe to workflow progress updates and workflow changes
    if connected?(socket) do
      ProgressTracker.subscribe()
      Workflows.subscribe()
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

      filters = default_filters()
      filtered_workflows = apply_workflow_filters(workflows, filters)

      socket =
        socket
        |> assign(:page_title, "Workflow Runner")
        |> assign(:workflows, workflows)
        |> assign(:workflow_filters, filters)
        |> assign(:filtered_workflows, filtered_workflows)
        |> assign(:active_executions, active_executions)
        |> assign(:recent_executions, recent_executions)
        |> assign(:selected_execution_id, nil)
        |> assign(:execution_events, [])

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params)
      |> assign(:current_path, URI.parse(uri).path || "/dashboard/workflows")

    account_id = socket.assigns.current_account_id

    # Reload data when account changes
    workflows = list_workflows(account_id)
    active_executions = list_active_executions(account_id)
    recent_executions = list_recent_executions(account_id, limit: 10)

    filters = socket.assigns[:workflow_filters] || default_filters()
    filtered_workflows = apply_workflow_filters(workflows, filters)

    socket =
      socket
      |> assign(:workflows, workflows)
      |> assign(:filtered_workflows, filtered_workflows)
      |> assign(:active_executions, active_executions)
      |> assign(:recent_executions, recent_executions)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_workflow", _params, socket) do
    account_id = socket.assigns.current_account_id
    user_id = socket.assigns.current_scope.user && socket.assigns.current_scope.user.id

    attrs = default_workflow_attrs(account_id, user_id)

    case Workflows.create_workflow(attrs) do
      {:ok, workflow} ->
        workflows = list_workflows(account_id)
        filters = socket.assigns.workflow_filters
        filtered = apply_workflow_filters(workflows, filters)

        socket =
          socket
          |> assign(:workflows, workflows)
          |> assign(:filtered_workflows, filtered)
          |> put_flash(:info, "Created workflow #{workflow.name}")
          |> push_navigate(
            to:
              PropertyRoutes.workflow_edit_path(
                socket.assigns.current_property_id,
                workflow.id
              )
          )

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create workflow: #{format_errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("filter_workflows", %{"filters" => filters_params}, socket) do
    filters = normalize_filters(filters_params)
    filtered = apply_workflow_filters(socket.assigns.workflows, filters)

    {:noreply,
     socket
     |> assign(:workflow_filters, filters)
     |> assign(:filtered_workflows, filtered)}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    filters = default_filters()
    filtered = apply_workflow_filters(socket.assigns.workflows, filters)

    {:noreply,
     socket
     |> assign(:workflow_filters, filters)
     |> assign(:filtered_workflows, filtered)}
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
  def handle_event("delete_workflow", %{"id" => workflow_id}, socket) do
    account_id = socket.assigns.current_account_id

    case Workflows.get_workflow(workflow_id, account_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Workflow not found")}

      workflow ->
        case Workflows.delete_workflow(workflow) do
          {:ok, _deleted_workflow} ->
            # Reload workflows list
            workflows = list_workflows(account_id)
            filters = socket.assigns.workflow_filters
            filtered = apply_workflow_filters(workflows, filters)

            socket =
              socket
              |> assign(:workflows, workflows)
              |> assign(:filtered_workflows, filtered)
              |> put_flash(:info, "Workflow deleted successfully")

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete workflow")}
        end
    end
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
    filtered = apply_workflow_filters(workflows, socket.assigns.workflow_filters)

    socket =
      socket
      |> assign(:workflows, workflows)
      |> assign(:filtered_workflows, filtered)

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

  defp default_workflow_attrs(account_id, user_id) do
    now = DateTime.utc_now()
    timestamp = Calendar.strftime(now, "%b %-d · %I:%M %p")

    %{
      name: "Untitled Workflow (#{timestamp})",
      description: "Auto-generated workflow",
      status: :draft,
      account_id: account_id,
      created_by_id: user_id,
      definition: default_workflow_definition()
    }
  end

  defp default_workflow_definition do
    %{
      "version" => "1.0",
      "steps" => [
        %{
          "id" => "step_1",
          "type" => "test",
          "name" => "New Step",
          "config" => %{"delay_ms" => 1000},
          "position" => %{"x" => 0, "y" => 0}
        }
      ],
      "connections" => []
    }
  end

  defp apply_workflow_filters(workflows, %{query: query, status: status}) do
    workflows
    |> Enum.filter(fn workflow ->
      matches_status =
        status == "all" || Atom.to_string(workflow.status) == status

      normalized_query = String.downcase(query || "")

      matches_query =
        normalized_query == "" or
          String.contains?(String.downcase(workflow.name), normalized_query) or
          (workflow.description &&
             String.contains?(String.downcase(workflow.description), normalized_query))

      matches_status and matches_query
    end)
  end

  defp default_filters, do: %{query: "", status: "all"}

  defp normalize_filters(params) do
    query =
      params
      |> Map.get("query", "")
      |> to_string()
      |> String.trim()

    status =
      params
      |> Map.get("status", "all")
      |> to_string()
      |> case do
        "draft" -> "draft"
        "published" -> "published"
        "archived" -> "archived"
        _ -> "all"
      end

    %{query: query, status: status}
  end

  defp workflow_stats(workflows) do
    total = length(workflows)
    published = Enum.count(workflows, &(&1.status == :published))
    draft = Enum.count(workflows, &(&1.status == :draft))
    last_updated = workflows |> Enum.max_by(& &1.updated_at, fn -> nil end)

    %{
      total: total,
      published: published,
      draft: draft,
      last_updated_at: last_updated && last_updated.updated_at
    }
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
      :execution_completed -> "hero-check"
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
      :execution_completed -> "text-green-600"
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

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
