defmodule GscAnalytics.SyncTestHelpers do
  @moduledoc """
  Minimal test helpers for progress tracking tests.

  Provides essential utilities to reduce boilerplate when testing
  sync progress functionality across GenServer, Sync, and LiveView layers.
  """

  @doc """
  Calculate progress percentage like LiveView does.

  This matches the calculation in DashboardSyncLive.assign_progress/2
  to ensure tests verify the actual user-visible percentage.
  """
  def calculate_percent(job) when is_nil(job), do: 0.0

  def calculate_percent(job) do
    total = job.total_steps || 0
    completed = job.completed_steps || 0
    status = job.status || :running

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
  end

  @doc """
  Subscribe to sync progress PubSub topic.

  Call this in test setup to receive {:sync_progress, payload} messages.
  """
  def subscribe_to_progress do
    Phoenix.PubSub.subscribe(GscAnalytics.PubSub, "gsc_sync_progress")
  end

  @doc """
  Assert that a progress event of the given type was received.

  ## Examples

      assert_progress_event(:step_completed)
      assert_progress_event(:finished, timeout: 500)
  """
  def assert_progress_event(type, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 100)

    receive do
      {:sync_progress, %{type: received_type} = payload} when received_type == type ->
        payload
    after
      timeout ->
        raise ExUnit.AssertionError,
          message: "Expected to receive progress event of type #{inspect(type)}"
    end
  end

  @doc """
  Clear all pending progress messages from the mailbox.

  Useful in test setup to prevent messages from previous tests
  from interfering with the current test.
  """
  def flush_progress_messages do
    receive do
      {:sync_progress, _} -> flush_progress_messages()
    after
      0 -> :ok
    end
  end
end
