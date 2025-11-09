defmodule GscAnalyticsWeb.DashboardWorkflowBuilderLive do
  @moduledoc """
  LiveView for the workflow builder - visual node-based workflow editor.

  Features:
  - React Flow integration via LiveView hooks
  - Real-time updates via PubSub
  - Auto-save and manual save
  - Dirty state tracking
  """

  use GscAnalyticsWeb, :live_view

  alias GscAnalytics.Repo
  alias GscAnalytics.Workflows
  alias GscAnalytics.Schemas.Workflow
  alias GscAnalyticsWeb.Live.AccountHelpers

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    # Subscribe to workflow changes
    if connected?(socket), do: Workflows.subscribe()

    {socket, account, _property} =
      AccountHelpers.init_account_and_property_assigns(socket, %{})

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
      # Load workflow
      case Workflows.get_workflow(workflow_id, account.id) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Workflow not found")
           |> redirect(to: ~p"/dashboard/workflows")}

        workflow ->
          socket =
            socket
            |> assign(:current_path, "/dashboard/workflows/#{workflow_id}/edit")
            |> assign(:page_title, "Edit Workflow: #{workflow.name}")
            |> assign(:workflow, workflow)
            |> assign(:workflow_id, workflow_id)
            |> assign(:is_dirty, false)
            |> assign(:last_saved_at, workflow.updated_at)

          {:ok, socket}
      end
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> AccountHelpers.assign_current_account(params)
      |> AccountHelpers.assign_current_property(params)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_workflow", %{"definition" => definition}, socket) do
    workflow = socket.assigns.workflow

    case Workflows.update_workflow(workflow, %{definition: definition}) do
      {:ok, updated_workflow} ->
        socket =
          socket
          |> assign(:workflow, updated_workflow)
          |> assign(:is_dirty, false)
          |> assign(:last_saved_at, updated_workflow.updated_at)
          |> put_flash(:info, "Workflow saved successfully")

        # Push update to React (workflow will update via PubSub too, but this is immediate)
        {:noreply, push_event(socket, "update_workflow", %{workflow: updated_workflow})}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to save workflow: #{format_errors(changeset)}")}
    end
  end

  @impl true
  def handle_event("auto_save_workflow", %{"definition" => definition}, socket) do
    workflow = socket.assigns.workflow

    case Workflows.update_workflow(workflow, %{definition: definition}) do
      {:ok, updated_workflow} ->
        socket =
          socket
          |> assign(:workflow, updated_workflow)
          |> assign(:is_dirty, false)
          |> assign(:last_saved_at, updated_workflow.updated_at)

        {:noreply, socket}

      {:error, _changeset} ->
        # Silent failure for auto-save - don't spam user with errors
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:workflow_event, %{workflow: workflow, event: _event_type}}, socket) do
    # Reload workflow when it's updated by another source
    if workflow.id == socket.assigns.workflow_id do
      socket =
        socket
        |> assign(:workflow, workflow)
        |> push_event("update_workflow", %{workflow: workflow})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  ## Private Helpers

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
    |> Enum.map(fn {field, errors} ->
      "#{field}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("; ")
  end
end
