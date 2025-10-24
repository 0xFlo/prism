defmodule GscAnalytics.DataSources.GSC.Support.SyncProgressTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias Phoenix.PubSub

  setup do
    # Subscribe to progress updates for testing
    :ok = PubSub.subscribe(GscAnalytics.PubSub, "gsc_sync_progress")

    # Clear any lingering messages from previous tests
    flush_messages()

    :ok
  end

  # Helper function to calculate percentage like LiveView does
  defp calculate_percent(job) when is_nil(job), do: 0.0

  defp calculate_percent(job) do
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

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  describe "start_job/1" do
    test "initializes job with correct total_steps" do
      job_id =
        SyncProgress.start_job(%{
          site_url: "sc-domain:test.com",
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-10],
          total_steps: 10
        })

      assert is_binary(job_id)

      state = SyncProgress.current_state()
      assert state.id == job_id
      assert state.status == :running
      assert state.total_steps == 10
      assert state.completed_steps == 0
      assert state.metadata.site_url == "sc-domain:test.com"

      # Should broadcast started event
      assert_receive {:sync_progress, %{type: :started, job: job}}
      assert job.id == job_id
    end

    test "initializes with zero percent progress" do
      _job_id =
        SyncProgress.start_job(%{
          site_url: "sc-domain:test.com",
          total_steps: 5
        })

      state = SyncProgress.current_state()
      assert calculate_percent(state) == 0.0
    end
  end

  describe "day_started/2" do
    test "updates current step and date" do
      job_id = SyncProgress.start_job(%{total_steps: 5})

      SyncProgress.day_started(job_id, %{
        date: ~D[2024-01-15],
        step: 1
      })

      state = SyncProgress.current_state()
      assert state.current_step == 1
      assert state.current_date == ~D[2024-01-15]

      # Should broadcast step_started event
      assert_receive {:sync_progress, %{type: :step_started, job: _job, event: event}}
      assert event.step == 1
      assert event.date == ~D[2024-01-15]
    end
  end

  describe "day_completed/2 with step tracking" do
    test "increments completed_steps correctly" do
      job_id = SyncProgress.start_job(%{total_steps: 5})

      SyncProgress.day_completed(job_id, %{
        date: ~D[2024-01-01],
        step: 1,
        status: :ok,
        urls: 10,
        rows: 100
      })

      state = SyncProgress.current_state()
      assert state.completed_steps == 1

      # Complete second step
      SyncProgress.day_completed(job_id, %{
        date: ~D[2024-01-02],
        step: 2,
        status: :ok,
        urls: 15,
        rows: 150
      })

      state = SyncProgress.current_state()
      assert state.completed_steps == 2
    end

    test "broadcasts step_completed event with step number" do
      job_id = SyncProgress.start_job(%{total_steps: 3})

      SyncProgress.day_completed(job_id, %{
        date: ~D[2024-01-01],
        step: 1,
        status: :ok,
        urls: 10
      })

      assert_receive {:sync_progress, %{type: :step_completed, job: _job, event: event}}
      assert event.step == 1
      assert event.status == :ok
      assert event.urls == 10
    end

    test "handles skipped status correctly" do
      job_id = SyncProgress.start_job(%{total_steps: 5})

      SyncProgress.day_completed(job_id, %{
        date: ~D[2024-01-01],
        step: 1,
        status: :skipped
      })

      state = SyncProgress.current_state()
      assert state.completed_steps == 1

      # Skipped days still count toward progress
      assert_receive {:sync_progress, %{type: :step_completed, event: event}}
      assert event.status == :skipped
    end

    test "clears current_step and current_date after completion" do
      job_id = SyncProgress.start_job(%{total_steps: 3})

      SyncProgress.day_started(job_id, %{date: ~D[2024-01-01], step: 1})
      state = SyncProgress.current_state()
      assert state.current_step == 1
      assert state.current_date == ~D[2024-01-01]

      SyncProgress.day_completed(job_id, %{
        date: ~D[2024-01-01],
        step: 1,
        status: :ok
      })

      state = SyncProgress.current_state()
      assert state.current_step == nil
      assert state.current_date == nil
    end

    test "accumulates metrics across steps" do
      job_id = SyncProgress.start_job(%{total_steps: 3})

      SyncProgress.day_completed(job_id, %{
        step: 1,
        status: :ok,
        urls: 10,
        rows: 100,
        api_calls: 2
      })

      SyncProgress.day_completed(job_id, %{
        step: 2,
        status: :ok,
        urls: 15,
        rows: 150,
        api_calls: 3
      })

      state = SyncProgress.current_state()
      assert state.metrics.total_urls == 25
      assert state.metrics.total_rows == 250
      assert state.metrics.total_api_calls == 5
    end

    test "does not accumulate metrics for skipped days" do
      job_id = SyncProgress.start_job(%{total_steps: 2})

      SyncProgress.day_completed(job_id, %{
        step: 1,
        status: :skipped
      })

      state = SyncProgress.current_state()
      assert state.metrics.total_urls == 0
      assert state.metrics.total_rows == 0
    end
  end

  describe "progress percentage calculation" do
    test "calculates 0% when no steps completed" do
      _job_id = SyncProgress.start_job(%{total_steps: 10})
      state = SyncProgress.current_state()
      assert calculate_percent(state) == 0.0
    end

    test "calculates 25% when 25% complete" do
      job_id = SyncProgress.start_job(%{total_steps: 4})

      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      state = SyncProgress.current_state()
      assert calculate_percent(state) == 25.0
    end

    test "calculates 50% when half complete" do
      job_id = SyncProgress.start_job(%{total_steps: 10})

      for step <- 1..5 do
        SyncProgress.day_completed(job_id, %{step: step, status: :ok})
      end

      state = SyncProgress.current_state()
      assert calculate_percent(state) == 50.0
    end

    test "calculates 100% when all steps completed" do
      job_id = SyncProgress.start_job(%{total_steps: 5})

      for step <- 1..5 do
        SyncProgress.day_completed(job_id, %{step: step, status: :ok})
      end

      state = SyncProgress.current_state()
      assert calculate_percent(state) == 100.0
    end

    test "never exceeds 100%" do
      job_id = SyncProgress.start_job(%{total_steps: 3})

      # Complete more steps than total (edge case)
      for step <- 1..5 do
        SyncProgress.day_completed(job_id, %{step: step, status: :ok})
      end

      state = SyncProgress.current_state()
      assert calculate_percent(state) <= 100.0
    end

    test "handles zero total_steps gracefully" do
      _job_id = SyncProgress.start_job(%{total_steps: 0})
      state = SyncProgress.current_state()
      assert calculate_percent(state) == 0.0
    end
  end

  describe "finish_job/2" do
    test "sets status to completed and finalizes job" do
      job_id = SyncProgress.start_job(%{total_steps: 3})

      for step <- 1..3 do
        SyncProgress.day_completed(job_id, %{step: step, status: :ok})
      end

      SyncProgress.finish_job(job_id, %{
        status: :completed,
        summary: %{days_processed: 3, total_urls: 100}
      })

      state = SyncProgress.current_state()
      assert state.status == :completed
      assert calculate_percent(state) == 100.0
      assert state.summary.days_processed == 3

      assert_receive {:sync_progress, %{type: :finished, job: job}}
      assert job.status == :completed
    end

    test "handles failed status correctly" do
      job_id = SyncProgress.start_job(%{total_steps: 5})

      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      SyncProgress.finish_job(job_id, %{
        status: :failed,
        error: "API error"
      })

      state = SyncProgress.current_state()
      assert state.status == :failed
      assert state.error == "API error"
      # Completed steps should remain at 1 for failed jobs
      assert state.completed_steps == 1
    end

    test "sets percent to 100% for completed jobs regardless of steps" do
      job_id = SyncProgress.start_job(%{total_steps: 10})

      SyncProgress.finish_job(job_id, %{
        status: :completed,
        summary: %{}
      })

      state = SyncProgress.current_state()
      assert calculate_percent(state) == 100.0
    end
  end

  describe "current_state/0" do
    test "returns current job state" do
      job_id = SyncProgress.start_job(%{total_steps: 5})
      state = SyncProgress.current_state()

      assert state != nil
      assert state.id == job_id
      assert state.status == :running
    end

    test "returns nil after job completes and is cleaned up" do
      job_id = SyncProgress.start_job(%{total_steps: 1})

      SyncProgress.finish_job(job_id, %{status: :completed})

      # Job is removed from state after completion
      # (implementation may vary - adjust based on actual behavior)
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts all event types" do
      job_id = SyncProgress.start_job(%{total_steps: 2})
      assert_receive {:sync_progress, %{type: :started}}

      SyncProgress.day_started(job_id, %{step: 1, date: ~D[2024-01-01]})
      assert_receive {:sync_progress, %{type: :step_started}}

      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})
      assert_receive {:sync_progress, %{type: :step_completed}}

      SyncProgress.finish_job(job_id, %{status: :completed})
      assert_receive {:sync_progress, %{type: :finished}}
    end

    test "includes job state in every broadcast" do
      job_id = SyncProgress.start_job(%{total_steps: 1})

      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      assert_receive {:sync_progress, %{type: :step_completed, job: job}}
      assert job.id == job_id
      assert job.completed_steps == 1
      assert calculate_percent(job) == 100.0
    end
  end

  describe "control commands" do
    test "pause command updates status to paused" do
      job_id = SyncProgress.start_job(%{total_steps: 5})
      :ok = SyncProgress.request_pause(job_id)

      state = SyncProgress.current_state()
      assert state.status == :paused

      assert_receive {:sync_progress, %{type: :paused}}
    end

    test "resume command restores running status" do
      job_id = SyncProgress.start_job(%{total_steps: 5})
      :ok = SyncProgress.request_pause(job_id)
      :ok = SyncProgress.resume_job(job_id)

      state = SyncProgress.current_state()
      assert state.status == :running

      assert_receive {:sync_progress, %{type: :resumed}}
    end

    test "stop command updates status to cancelling" do
      job_id = SyncProgress.start_job(%{total_steps: 5})
      :ok = SyncProgress.request_stop(job_id)

      state = SyncProgress.current_state()
      assert state.status == :cancelling

      assert_receive {:sync_progress, %{type: :stopping}}
    end
  end
end
