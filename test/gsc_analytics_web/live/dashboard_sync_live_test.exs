defmodule GscAnalyticsWeb.DashboardSyncLiveTest do
  use GscAnalyticsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias Phoenix.PubSub

  setup :register_and_log_in_user

  test "renders sync status page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard/sync")

    assert html =~ "Sync Status"
    assert html =~ "gsc-manual-sync"
  end

  describe "progress tracking" do
    test "displays progress percentage when job is running", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/sync")

      # Start a job
      job_id = SyncProgress.start_job(%{total_steps: 4})

      # Complete 2 of 4 steps (50%)
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})
      SyncProgress.day_completed(job_id, %{step: 2, status: :ok})

      # LiveView should update via PubSub
      assert render(view) =~ "50.0%"
    end

    test "displays completed steps counter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/sync")

      job_id = SyncProgress.start_job(%{total_steps: 5})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      # Should show "1/5"
      assert render(view) =~ "1/5"
    end

    test "progress bar width reflects percentage", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/sync")

      job_id = SyncProgress.start_job(%{total_steps: 4})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      # Should have width style set to 25%
      html = render(view)
      assert html =~ "width: 25.0%"
    end

    test "updates when receiving PubSub broadcasts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/sync")

      # Manually broadcast progress update
      job = %{
        id: "test-job",
        status: :running,
        total_steps: 10,
        completed_steps: 3,
        current_step: nil,
        current_date: nil,
        started_at: DateTime.utc_now(),
        finished_at: nil,
        metadata: %{},
        events: [],
        metrics: %{total_rows: 0, total_api_calls: 0}
      }

      PubSub.broadcast(GscAnalytics.PubSub, "gsc_sync_progress", {
        :sync_progress,
        %{type: :step_completed, job: job}
      })

      # Should show 30% (3/10)
      assert render(view) =~ "30.0%"
    end

    test "mounts with existing job state", %{conn: conn} do
      # Start job before mounting LiveView
      job_id = SyncProgress.start_job(%{total_steps: 2})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      {:ok, _view, html} = live(conn, ~p"/dashboard/sync")

      # Should immediately show 50% progress
      assert html =~ "50.0%"
      assert html =~ "1/2"
    end
  end
end
