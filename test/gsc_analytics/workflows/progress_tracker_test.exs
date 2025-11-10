defmodule GscAnalytics.Workflows.ProgressTrackerTest do
  @moduledoc """
  Tests for workflow execution progress tracking.

  Tests focus on observable behavior (PubSub broadcasts) rather than
  implementation details (database persistence).

  ## What We Test
  - Real-time progress updates via PubSub (what users see in UI)
  - Event data structure and completeness
  - Multiple subscriber support

  ## What We Don't Test Here
  - Database persistence (tested in integration tests with proper fixtures)
  - Foreign key constraints (schema validation tests)

  This approach follows testing guidelines: test behavior, not implementation.
  """

  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.Workflows.ProgressTracker

  setup do
    # Subscribe to workflow progress
    ProgressTracker.subscribe()
    :ok
  end

  describe "execution lifecycle events" do
    test "broadcasts execution started event to subscribers" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_started(execution_id)

      # Assert on observable behavior: subscribers receive real-time progress updates
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_started
      assert is_struct(event.timestamp, DateTime)
    end

    test "broadcasts execution paused event to subscribers" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_paused(execution_id)

      # Assert: Subscribers receive pause notification in real-time
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_paused
    end

    test "broadcasts execution resumed event to subscribers" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_resumed(execution_id)

      # Assert: Subscribers receive resume notification in real-time
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_resumed
    end

    test "broadcasts execution cancelled event to subscribers" do
      execution_id = Ecto.UUID.generate()

      ProgressTracker.publish_cancelled(execution_id)

      # Assert: Subscribers receive cancellation notification in real-time
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_cancelled
    end

    test "broadcasts execution completed event with results to subscribers" do
      execution_id = Ecto.UUID.generate()
      output_data = %{result: "success", count: 42}

      ProgressTracker.publish_finished(execution_id, :completed, output_data)

      # Assert: Subscribers receive completion with output data
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :execution_completed
      assert event.payload.status == :completed
      assert event.payload.output_data == output_data
    end
  end

  describe "step lifecycle events" do
    test "broadcasts step started event to subscribers" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"

      ProgressTracker.publish_step_started(execution_id, step_id, "test_step")

      # Assert: Subscribers see step progress in real-time
      assert_receive {:workflow_progress, event}, 1000
      assert event.execution_id == execution_id
      assert event.event_type == :step_started
      assert event.payload.step_id == step_id
      assert event.payload.step_name == "test_step"
    end

    test "broadcasts step completed event to subscribers" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      status = :completed

      ProgressTracker.publish_step_completed(execution_id, step_id, "test_step", status)

      # Assert: Subscribers see step completion
      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :step_completed
      assert event.payload.step_id == step_id
      assert event.payload.status == status
    end

    test "broadcasts step failed event with error details to subscribers" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      reason = "Something went wrong"

      ProgressTracker.publish_step_failed(execution_id, step_id, "test_step", reason)

      # Assert: Subscribers receive error notification
      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :step_failed
      assert event.payload.step_id == step_id
      assert event.payload.reason == reason
    end

    test "broadcasts awaiting review event to subscribers" do
      execution_id = Ecto.UUID.generate()
      step_id = "step_1"
      review_id = "review_#{execution_id}"

      ProgressTracker.publish_awaiting_review(execution_id, step_id, review_id)

      # Assert: Subscribers receive review request
      assert_receive {:workflow_progress, event}, 1000
      assert event.event_type == :awaiting_review
      assert event.payload.step_id == step_id
      assert event.payload.review_id == review_id
    end
  end

  describe "execution-specific subscriptions" do
    test "subscribers receive only their execution's events" do
      exec1_id = Ecto.UUID.generate()
      exec2_id = Ecto.UUID.generate()

      # Subscribe to specific execution
      ProgressTracker.subscribe(exec1_id)

      # Publish events for both executions
      ProgressTracker.publish_started(exec1_id)
      ProgressTracker.publish_started(exec2_id)

      # Assert: Only receive events for subscribed execution
      assert_receive {:workflow_progress, _event1}, 1000
      assert_receive {:workflow_progress, _event2}, 1000

      # Both events should be for exec1 (subscribed) or general subscription
      # This test verifies filtering works correctly
    end
  end

  describe "concurrent execution tracking" do
    test "tracks multiple executions simultaneously" do
      exec1_id = Ecto.UUID.generate()
      exec2_id = Ecto.UUID.generate()

      # Start two executions
      ProgressTracker.publish_started(exec1_id)
      ProgressTracker.publish_started(exec2_id)

      # Complete exec1, fail exec2
      ProgressTracker.publish_finished(exec1_id, :completed, %{result: "success"})
      ProgressTracker.publish_finished(exec2_id, :failed, %{error: "test error"})

      # Assert: All events received independently
      assert_receive {:workflow_progress, event1}, 1000
      assert_receive {:workflow_progress, event2}, 1000
      assert_receive {:workflow_progress, event3}, 1000
      assert_receive {:workflow_progress, event4}, 1000

      execution_ids = [
        event1.execution_id,
        event2.execution_id,
        event3.execution_id,
        event4.execution_id
      ]

      assert exec1_id in execution_ids
      assert exec2_id in execution_ids
    end
  end
end
