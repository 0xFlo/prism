defmodule GscAnalytics.Workflows.ProgressTrackerTest do
  @moduledoc """
  Tests for workflow execution progress tracking.

  Verifies:
  - PubSub broadcasting works correctly
  - Events are persisted to database
  - Multiple subscribers receive events
  - Event persistence for crash recovery
  """

  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.Repo
  alias GscAnalytics.Workflows.{ProgressTracker, ExecutionEvent}

  setup do
    # Subscribe to workflow progress
    ProgressTracker.subscribe()
    :ok
  end

  describe "execution lifecycle events" do
    test "publishes and persists execution started event" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_started(execution_id)

      # Verify PubSub broadcast received
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_started

      # Verify DB persistence
      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :execution_started)
        )
      end)
    end

    test "publishes and persists execution paused event" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_paused(execution_id)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :execution_paused

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :execution_paused)
        )
      end)
    end

    test "publishes and persists execution resumed event" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_resumed(execution_id)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :execution_resumed

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :execution_resumed)
        )
      end)
    end

    test "publishes and persists execution cancelled event" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_cancelled(execution_id)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :execution_cancelled

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :execution_cancelled)
        )
      end)
    end

    test "publishes and persists execution finished event" do
      execution_id = Ecto.UUID.generate()
      output_data = %{result: "success", count: 42}

      ProgressTracker.publish_finished(execution_id, :completed, output_data)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :execution_completed
      assert event.payload.status == :completed
      assert event.payload.output_data == output_data

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :execution_completed)
        )
      end)
    end
  end

  describe "step lifecycle events" do
    test "publishes and persists step started event" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      step_name = "Fetch Data"

      ProgressTracker.publish_step_started(execution_id, step_id, step_name)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :step_started
      assert event.payload.step_id == step_id
      assert event.payload.step_name == step_name

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :step_started &&
              &1.step_id == step_id)
        )
      end)
    end

    test "publishes and persists step completed event" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      step_name = "Process Data"

      ProgressTracker.publish_step_completed(execution_id, step_id, step_name, :ok)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :step_completed
      assert event.payload.step_id == step_id
      assert event.payload.status == :ok

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :step_completed &&
              &1.step_id == step_id)
        )
      end)
    end

    test "publishes and persists step failed event" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      step_name = "API Call"
      reason = "Network timeout"

      ProgressTracker.publish_step_failed(execution_id, step_id, step_name, reason)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :step_failed
      assert event.payload.step_id == step_id
      assert event.payload.reason == inspect(reason)

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)

        Enum.any?(
          events,
          &(&1.execution_id == execution_id && &1.event_type == :step_failed &&
              &1.step_id == step_id)
        )
      end)
    end

    test "publishes and persists awaiting review event" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      review_id = Ecto.UUID.generate()

      ProgressTracker.publish_awaiting_review(execution_id, step_id, review_id)

      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :awaiting_review
      assert event.payload.step_id == step_id
      assert event.payload.review_id == review_id

      assert_eventually(fn ->
        events = Repo.all(ExecutionEvent)
        Enum.any?(events, &(&1.execution_id == execution_id && &1.event_type == :awaiting_review))
      end)
    end
  end

  describe "execution-specific subscriptions" do
    test "subscribers receive only their execution's events" do
      execution_id_1 = Ecto.UUID.generate()
      execution_id_2 = Ecto.UUID.generate()

      # Subscribe to specific execution
      ProgressTracker.subscribe(execution_id_1)

      # Publish to both executions
      ProgressTracker.publish_started(execution_id_1)
      ProgressTracker.publish_started(execution_id_2)

      # Should receive both from global subscription (in setup)
      assert_receive {:workflow_progress, event1}, 1000
      assert_receive {:workflow_progress, event2}, 1000

      # Should receive execution_id_1 from specific subscription
      assert_receive {:workflow_progress, event3}, 1000
      assert event3.execution_id == execution_id_1

      # Should NOT receive execution_id_2 from specific subscription
      refute_receive {:workflow_progress, %{execution_id: ^execution_id_2}}, 100
    end
  end

  describe "crash recovery via event history" do
    test "events can be read from database for recovery" do
      execution_id = Ecto.UUID.generate()

      # Simulate a workflow execution with multiple events
      ProgressTracker.publish_started(execution_id)
      ProgressTracker.publish_step_started(execution_id, "step_1", "Step 1")
      ProgressTracker.publish_step_completed(execution_id, "step_1", "Step 1", :ok)
      ProgressTracker.publish_finished(execution_id, :completed, %{})

      # Wait for all events to be persisted
      :timer.sleep(100)

      # Simulate crash recovery: read events from DB
      events =
        ExecutionEvent
        |> ExecutionEvent.for_execution(execution_id)
        |> ExecutionEvent.chronological()
        |> Repo.all()

      # Verify we can reconstruct the execution state
      assert length(events) == 4
      event_types = Enum.map(events, & &1.event_type)
      assert :execution_started in event_types
      assert :step_started in event_types
      assert :step_completed in event_types
      assert :execution_completed in event_types

      # Verify step IDs are tracked
      step_events = Enum.filter(events, &(&1.step_id == "step_1"))
      assert length(step_events) == 2
    end
  end

  describe "concurrent execution tracking" do
    test "tracks multiple executions simultaneously" do
      execution_id_1 = Ecto.UUID.generate()
      execution_id_2 = Ecto.UUID.generate()
      execution_id_3 = Ecto.UUID.generate()

      # Start multiple executions
      ProgressTracker.publish_started(execution_id_1)
      ProgressTracker.publish_started(execution_id_2)
      ProgressTracker.publish_started(execution_id_3)

      # Complete them in different orders
      ProgressTracker.publish_finished(execution_id_2, :completed, %{})
      ProgressTracker.publish_finished(execution_id_1, :completed, %{})
      ProgressTracker.publish_finished(execution_id_3, :failed, %{})

      # Wait for persistence
      :timer.sleep(100)

      # Verify all executions tracked
      events = Repo.all(ExecutionEvent)
      execution_ids = Enum.map(events, & &1.execution_id) |> Enum.uniq()

      assert execution_id_1 in execution_ids
      assert execution_id_2 in execution_ids
      assert execution_id_3 in execution_ids
    end
  end

  ## Helper Functions

  defp assert_eventually(fun, timeout \\ 2000, interval \\ 50) do
    start_time = System.monotonic_time(:millisecond)

    assert_eventually_loop(fun, start_time, timeout, interval)
  end

  defp assert_eventually_loop(fun, start_time, timeout, interval) do
    if fun.() do
      :ok
    else
      elapsed = System.monotonic_time(:millisecond) - start_time

      if elapsed >= timeout do
        flunk("Condition not met within #{timeout}ms")
      else
        :timer.sleep(interval)
        assert_eventually_loop(fun, start_time, timeout, interval)
      end
    end
  end
end
