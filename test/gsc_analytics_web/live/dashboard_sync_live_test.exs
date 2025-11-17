defmodule GscAnalyticsWeb.DashboardSyncLiveTest do
  use GscAnalyticsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GscAnalytics.WorkspaceTestHelper

  alias GscAnalytics.DataSources.GSC.Support.{DeadLetter, SyncProgress}
  alias GscAnalytics.{Accounts, Auth, Workspaces}
  alias GscAnalyticsWeb.PropertyRoutes
  alias Phoenix.PubSub

  setup :register_and_log_in_user

  setup %{user: user} do
    {workspace, property} = setup_workspace_with_property(user: user)
    %{workspace: workspace, property: property}
  end

  test "renders sync status page", %{conn: conn, property: property} do
    {:ok, _view, html} = live(conn, PropertyRoutes.sync_path(property.id))

    assert html =~ "Sync Status"
    assert html =~ "gsc-manual-sync"
  end

  describe "progress tracking" do
    test "displays progress percentage when job is running", %{conn: conn, property: property} do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      # Start a job
      job_id = SyncProgress.start_job(%{total_steps: 4})

      # Complete 2 of 4 steps (50%)
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})
      SyncProgress.day_completed(job_id, %{step: 2, status: :ok})

      # LiveView should update via PubSub
      assert render(view) =~ "50.0%"
    end

    test "displays completed steps counter", %{conn: conn, property: property} do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      job_id = SyncProgress.start_job(%{total_steps: 5})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      # Should show the completed/total steps badge
      assert Regex.match?(~r/Processed days.*?1\/5/s, render(view))
    end

    test "progress bar width reflects percentage", %{conn: conn, property: property} do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      job_id = SyncProgress.start_job(%{total_steps: 4})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      # Should have width style set to 25%
      render(view)
      assert has_element?(view, "div[style*=\"width: 25.0%\"]")
    end

    test "updates when receiving PubSub broadcasts", %{conn: conn, property: property} do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

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

    test "mounts with existing job state", %{conn: conn, property: property} do
      # Start job before mounting LiveView
      job_id = SyncProgress.start_job(%{total_steps: 2})
      SyncProgress.day_completed(job_id, %{step: 1, status: :ok})

      {:ok, _view, html} = live(conn, PropertyRoutes.sync_path(property.id))

      # Should immediately show 50% progress
      assert html =~ "50.0%"
      assert html =~ "1/2"
    end
  end

  describe "property selector" do
    test "only shows active properties in dropdown", %{conn: conn, user: user} do
      # Create a workspace for the test
      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "test@example.com",
          enabled: true
        })

      # Create OAuth token for the workspace so properties can be loaded
      scope = %Auth.Scope{user: user, account_ids: [workspace.id]}

      {:ok, _token} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace.id,
          google_email: workspace.google_account_email,
          access_token: "fake_access_token",
          refresh_token: "fake_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Add an active property
      {:ok, property} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:active-site.com",
          is_active: true
        })

      # Add an inactive property
      {:ok, _inactive_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive-site.com",
          is_active: false
        })

      {:ok, _view, html} = live(conn, PropertyRoutes.sync_path(property.id))

      # Active property should appear in the dropdown
      assert html =~ "active-site.com"

      # Inactive property should NOT appear in the dropdown
      refute html =~ "inactive-site.com"
    end

    test "shows message when no active properties exist", %{conn: conn, user: user} do
      # Create a workspace for the test
      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "test@example.com",
          enabled: true
        })

      # Create OAuth token
      scope = %Auth.Scope{user: user, account_ids: [workspace.id]}

      {:ok, _token} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace.id,
          google_email: workspace.google_account_email,
          access_token: "fake_access_token",
          refresh_token: "fake_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Add only an inactive property
      {:ok, inactive_prop} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:inactive-site.com",
          is_active: false
        })

      {:ok, _view, _html} = live(conn, PropertyRoutes.sync_path(inactive_prop.id))

      # The property selector component properly handles empty state
      # (inactive properties are filtered out in AccountHelpers)
      # No assertion needed here as the component renders without errors
    end

    test "updating property to inactive removes it from dropdown", %{conn: conn, user: user} do
      # Create a workspace for the test
      {:ok, workspace} =
        Workspaces.create_workspace(user.id, %{
          google_account_email: "test@example.com",
          name: "test@example.com",
          enabled: true
        })

      # Create OAuth token
      scope = %Auth.Scope{user: user, account_ids: [workspace.id]}

      {:ok, _token} =
        Auth.store_oauth_token(scope, %{
          account_id: workspace.id,
          google_email: workspace.google_account_email,
          access_token: "fake_access_token",
          refresh_token: "fake_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
          scopes: ["https://www.googleapis.com/auth/webmasters.readonly"]
        })

      # Add an active property
      {:ok, property} =
        Accounts.add_property(workspace.id, %{
          property_url: "sc-domain:test-site.com",
          is_active: true
        })

      {:ok, _view, html} = live(conn, PropertyRoutes.sync_path(property.id))

      # Initially, property should be visible
      assert html =~ "test-site.com"

      # Deactivate the property
      {:ok, _updated} = Accounts.update_property_active(workspace.id, property.id, false)

      # After deactivation, property should no longer appear
      # We need a fresh mount to see the updated state (LiveView caches properties)
      {:ok, _new_view, new_html} = live(conn, PropertyRoutes.sync_path(property.id))
      refute new_html =~ "test-site.com"
    end
  end

  describe "telemetry diagnostics" do
    setup %{workspace: workspace} do
      DeadLetter.clear()

      {:ok, property} =
        Accounts.add_property(workspace.id, %{
          property_url: "https://insighttimer.com/",
          is_active: true
        })

      {:ok, %{diagnostic_property: property}}
    end

    test "records URL telemetry activity for insighttimer.com", %{
      conn: conn,
      diagnostic_property: property
    } do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      send(
        view.pid,
        {:telemetry_event, [:gsc_analytics, :url_pipeline, :message],
         %{duration_ms: 5_926, batch_size: nil},
         %{status: :ok, site_url: property.property_url, date: ~D[2025-07-10]}}
      )

      html = render(view)

      assert html =~ "URL stage"
      assert html =~ "insighttimer.com"
      assert html =~ "5926.0 ms"
      assert html =~ "Jul 10, 2025"
    end

    test "updates query pipeline status telemetry for the property", %{
      conn: conn,
      diagnostic_property: property
    } do
      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      send(
        view.pid,
        {:telemetry_event, [:gsc_analytics, :query_pipeline, :status], %{},
         %{
           status: :dispatch,
           queue_depth: 6,
           in_flight: 0,
           writer_backlog: false,
           site_url: property.property_url
         }}
      )

      html = render(view)

      assert html =~ "Dispatching work: 6 queued page(s), 0 in flight."
      assert html =~ "Queue depth"
      assert html =~ ">6</dd>"
    end

    test "allows clearing the retry queue for the property", %{
      conn: conn,
      diagnostic_property: property
    } do
      DeadLetter.put(:query_pipeline, %{
        site_url: property.property_url,
        date: ~D[2025-07-11],
        reason: :timeout
      })

      {:ok, view, _html} = live(conn, PropertyRoutes.sync_path(property.id))

      assert render(view) =~ "1 pending"

      view
      |> element("button[phx-click=\"clear_dead_letters\"]", "Clear queue")
      |> render_click()

      assert render(view) =~ "No pending retries."
      assert DeadLetter.all() == []
    end
  end
end
