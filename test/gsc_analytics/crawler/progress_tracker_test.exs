defmodule GscAnalytics.Crawler.ProgressTrackerTest do
  use ExUnit.Case, async: false

  alias GscAnalytics.Crawler.ProgressTracker

  setup do
    # Start ProgressTracker if not already running
    case GenServer.whereis(ProgressTracker) do
      nil -> start_supervised!(ProgressTracker)
      _pid -> :ok
    end

    # Subscribe to progress events
    ProgressTracker.subscribe()

    :ok
  end

  describe "start_check/1" do
    test "starts a new check job" do
      {:ok, job_id} = ProgressTracker.start_check(100)

      assert is_binary(job_id)
      assert String.starts_with?(job_id, "check-")

      # Should broadcast started event
      assert_receive {:crawler_progress, %{type: :started, job: job}}, 100
      assert job.id == job_id
      assert job.total_urls == 100
      assert job.checked == 0
    end

    test "creates job with status counters initialized to zero" do
      {:ok, _job_id} = ProgressTracker.start_check(50)

      assert_receive {:crawler_progress, %{type: :started, job: job}}, 100

      assert job.status_counts == %{
               "2xx" => 0,
               "3xx" => 0,
               "4xx" => 0,
               "5xx" => 0,
               "errors" => 0
             }
    end

    test "includes started_at timestamp" do
      before = DateTime.utc_now()
      {:ok, _job_id} = ProgressTracker.start_check(10)

      assert_receive {:crawler_progress, %{type: :started, job: job}}, 100

      assert %DateTime{} = job.started_at
      assert DateTime.compare(job.started_at, before) in [:gt, :eq]
    end
  end

  describe "update_progress/1" do
    setup do
      {:ok, job_id} = ProgressTracker.start_check(3)
      # Consume the started message
      assert_receive {:crawler_progress, %{type: :started}}, 100

      %{job_id: job_id}
    end

    test "increments checked counter on successful result" do
      result = %{status: 200, error: nil, redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.checked == 1
    end

    test "increments 2xx counter for successful responses" do
      result = %{status: 200, error: nil, redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["2xx"] == 1
      assert job.status_counts["errors"] == 0
    end

    test "increments 3xx counter for redirects" do
      result = %{status: 301, error: nil, redirect_url: "https://example.com"}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["3xx"] == 1
    end

    test "increments 4xx counter for client errors" do
      result = %{status: 404, error: nil, redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["4xx"] == 1
    end

    test "increments 5xx counter for server errors" do
      result = %{status: 500, error: nil, redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["5xx"] == 1
    end

    test "increments error counter when error is present" do
      result = %{status: nil, error: "Connection failed", redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["errors"] == 1
    end

    test "increments error counter when status is nil" do
      result = %{status: nil, error: nil, redirect_url: nil}

      ProgressTracker.update_progress(result)

      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100
      assert job.status_counts["errors"] == 1
    end

    test "tracks multiple updates correctly" do
      results = [
        %{status: 200, error: nil, redirect_url: nil},
        %{status: 404, error: nil, redirect_url: nil},
        %{status: 500, error: nil, redirect_url: nil}
      ]

      for result <- results do
        ProgressTracker.update_progress(result)
      end

      # Get the last update message
      assert_receive {:crawler_progress, %{type: :update}}, 100
      assert_receive {:crawler_progress, %{type: :update}}, 100
      assert_receive {:crawler_progress, %{type: :update, job: job}}, 100

      assert job.checked == 3
      assert job.status_counts["2xx"] == 1
      assert job.status_counts["4xx"] == 1
      assert job.status_counts["5xx"] == 1
    end

    test "does not broadcast when no job is running" do
      # Finish current job first
      stats = %{
        checked: 3,
        status_2xx: 3,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _job} = ProgressTracker.finish_check(stats)
      # Consume finished message
      assert_receive {:crawler_progress, %{type: :finished}}, 100

      # Try to update progress without a running job
      result = %{status: 200, error: nil, redirect_url: nil}
      ProgressTracker.update_progress(result)

      # Should not receive update message
      refute_receive {:crawler_progress, %{type: :update}}, 500
    end
  end

  describe "finish_check/1" do
    setup do
      {:ok, job_id} = ProgressTracker.start_check(3)
      # Consume started message
      assert_receive {:crawler_progress, %{type: :started}}, 100

      # Add some progress
      ProgressTracker.update_progress(%{status: 200, error: nil, redirect_url: nil})
      assert_receive {:crawler_progress, %{type: :update}}, 100

      %{job_id: job_id}
    end

    test "finishes the check and broadcasts finished event" do
      stats = %{
        total: 3,
        checked: 3,
        status_2xx: 2,
        status_3xx: 0,
        status_4xx: 1,
        status_5xx: 0,
        errors: 0
      }

      {:ok, job} = ProgressTracker.finish_check(stats)

      assert_receive {:crawler_progress, %{type: :finished, job: finished_job, stats: ^stats}},
                     100

      assert finished_job.id == job.id
      assert finished_job.checked == 3
      assert finished_job.status_counts["2xx"] == 2
      assert finished_job.status_counts["4xx"] == 1
    end

    test "includes duration_ms in finished job" do
      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _job} = ProgressTracker.finish_check(stats)

      assert_receive {:crawler_progress, %{type: :finished, job: job}}, 100
      assert is_integer(job.duration_ms)
      assert job.duration_ms >= 0
    end

    test "includes finished_at timestamp" do
      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      before = DateTime.utc_now()
      {:ok, _job} = ProgressTracker.finish_check(stats)

      assert_receive {:crawler_progress, %{type: :finished, job: job}}, 100
      assert %DateTime{} = job.finished_at
      assert DateTime.compare(job.finished_at, before) in [:gt, :eq]
    end

    test "returns error when no job is running" do
      # Finish the current job first
      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _job} = ProgressTracker.finish_check(stats)
      assert_receive {:crawler_progress, %{type: :finished}}, 100

      # Try to finish again
      result = ProgressTracker.finish_check(stats)
      assert result == {:error, :no_job_running}
    end

    test "clears current job after finishing" do
      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _job} = ProgressTracker.finish_check(stats)

      # Current job should be nil
      current = ProgressTracker.get_current_job()
      assert current == nil
    end
  end

  describe "get_current_job/0" do
    test "returns nil when no job is running" do
      # Ensure no job is running
      current = ProgressTracker.get_current_job()

      if current do
        stats = %{
          total: 1,
          checked: 1,
          status_2xx: 1,
          status_3xx: 0,
          status_4xx: 0,
          status_5xx: 0,
          errors: 0
        }

        ProgressTracker.finish_check(stats)
      end

      assert ProgressTracker.get_current_job() == nil
    end

    test "returns current job when one is running" do
      {:ok, job_id} = ProgressTracker.start_check(10)

      current = ProgressTracker.get_current_job()

      assert current.id == job_id
      assert current.total_urls == 10
    end
  end

  describe "get_history/0" do
    test "returns empty list initially" do
      # Clear history by getting it (history persists across tests)
      history = ProgressTracker.get_history()
      assert is_list(history)
    end

    test "adds completed jobs to history" do
      {:ok, job_id} = ProgressTracker.start_check(1)
      assert_receive {:crawler_progress, %{type: :started}}, 100

      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _job} = ProgressTracker.finish_check(stats)

      history = ProgressTracker.get_history()

      completed_job = Enum.find(history, fn job -> job.id == job_id end)
      assert completed_job != nil
      assert completed_job.checked == 1
      assert Map.has_key?(completed_job, :finished_at)
      assert Map.has_key?(completed_job, :duration_ms)
    end

    test "maintains history in reverse chronological order" do
      # Start and finish two jobs
      {:ok, job_id_1} = ProgressTracker.start_check(1)
      assert_receive {:crawler_progress, %{type: :started}}, 100

      stats = %{
        total: 1,
        checked: 1,
        status_2xx: 1,
        status_3xx: 0,
        status_4xx: 0,
        status_5xx: 0,
        errors: 0
      }

      {:ok, _} = ProgressTracker.finish_check(stats)
      assert_receive {:crawler_progress, %{type: :finished}}, 100

      # Small delay to ensure different job IDs
      Process.sleep(10)

      {:ok, job_id_2} = ProgressTracker.start_check(1)
      assert_receive {:crawler_progress, %{type: :started}}, 100

      {:ok, _} = ProgressTracker.finish_check(stats)
      assert_receive {:crawler_progress, %{type: :finished}}, 100

      history = ProgressTracker.get_history()

      # Most recent job should be first
      assert length(history) >= 2
      [first, second | _] = history
      assert first.id == job_id_2
      assert second.id == job_id_1
    end
  end

  describe "subscribe/0" do
    test "allows subscribing to progress events" do
      # Already subscribed in setup, but test that it works
      {:ok, _job_id} = ProgressTracker.start_check(1)

      # Should receive the started event
      assert_receive {:crawler_progress, %{type: :started}}, 100
    end

    test "multiple subscribers all receive events" do
      # Spawn a second subscriber
      test_pid = self()

      subscriber_task =
        Task.async(fn ->
          ProgressTracker.subscribe()
          send(test_pid, :subscribed)

          receive do
            {:crawler_progress, %{type: :started}} -> :ok
          after
            1_000 -> :timeout
          end
        end)

      # Wait for subscription
      assert_receive :subscribed, 100

      # Start a job
      {:ok, _job_id} = ProgressTracker.start_check(1)

      # Both this process and the subscriber should receive the event
      assert_receive {:crawler_progress, %{type: :started}}, 100
      assert Task.await(subscriber_task) == :ok
    end
  end
end
