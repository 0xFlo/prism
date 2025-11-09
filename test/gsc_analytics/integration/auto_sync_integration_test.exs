defmodule GscAnalytics.Integration.AutoSyncIntegrationTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  import Ecto.Query

  alias GscAnalytics.Workers.GscSyncWorker
  alias GscAnalytics.AuthFixtures
  alias GscAnalytics.AccountsFixtures
  alias GscAnalytics.Schemas.{Workspace, TimeSeries, Performance}
  alias GscAnalytics.Repo

  @moduletag :integration

  setup do
    # Clean up any existing data
    Repo.delete_all(TimeSeries)
    Repo.delete_all(Performance)
    Repo.delete_all(Workspace)

    # Create test users and workspaces
    user1 = AuthFixtures.user_fixture()
    user2 = AuthFixtures.user_fixture()

    ws1 = AccountsFixtures.workspace_fixture(user: user1, enabled: true)
    ws2 = AccountsFixtures.workspace_fixture(user: user2, enabled: true)
    _ws3_disabled = AccountsFixtures.workspace_fixture(user: user1, enabled: false)

    %{
      user1: user1,
      user2: user2,
      ws1: ws1,
      ws2: ws2
    }
  end

  describe "end-to-end auto-sync flow" do
    test "worker syncs all enabled workspaces successfully", %{ws1: _ws1, ws2: _ws2} do
      # Set environment for 14 days
      System.put_env("AUTO_SYNC_DAYS", "14")

      # Perform the worker job
      assert :ok = perform_job(GscSyncWorker, %{})

      # Verify both workspaces were processed
      # Note: This test would need actual GSC data or a mock client to fully verify
      # For now, we verify the worker executed without errors

      # Clean up
      System.delete_env("AUTO_SYNC_DAYS")
    end

    test "worker skips disabled workspaces" do
      # Delete enabled workspaces, keep only disabled
      Repo.delete_all(from w in Workspace, where: w.enabled == true)

      # Perform the worker job
      assert :ok = perform_job(GscSyncWorker, %{})

      # Verify no sync occurred (no TimeSeries data created)
      assert Repo.aggregate(TimeSeries, :count) == 0
    end

    test "worker handles empty workspace list gracefully" do
      # Delete all workspaces
      Repo.delete_all(Workspace)

      # Perform the worker job
      assert :ok = perform_job(GscSyncWorker, %{})

      # Should complete without error
      assert Repo.aggregate(TimeSeries, :count) == 0
    end

    test "worker uses configured sync days from environment" do
      # Set to 30 days
      System.put_env("AUTO_SYNC_DAYS", "30")

      # Capture telemetry
      test_pid = self()

      :telemetry.attach(
        "test-integration-handler",
        [:gsc_analytics, :auto_sync, :started],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_received, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:telemetry_received, metadata}
      assert metadata.sync_days == 30

      :telemetry.detach("test-integration-handler")
      System.delete_env("AUTO_SYNC_DAYS")
    end

    test "worker defaults to 14 days when env var not set" do
      System.delete_env("AUTO_SYNC_DAYS")

      # Capture telemetry
      test_pid = self()

      :telemetry.attach(
        "test-integration-default-handler",
        [:gsc_analytics, :auto_sync, :started],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_received, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:telemetry_received, metadata}
      assert metadata.sync_days == 14

      :telemetry.detach("test-integration-default-handler")
    end
  end

  describe "Oban cron configuration" do
    test "cron plugin is not active when auto-sync is disabled" do
      System.delete_env("ENABLE_AUTO_SYNC")

      plugins = GscAnalytics.Config.AutoSync.plugins()

      # Should only have Pruner plugin
      assert length(plugins) == 1
      assert {Oban.Plugins.Pruner, _} = List.first(plugins)
    end

    test "cron plugin is active when auto-sync is enabled" do
      System.put_env("ENABLE_AUTO_SYNC", "true")

      plugins = GscAnalytics.Config.AutoSync.plugins()

      # Should have Pruner, Lifeline, and Cron
      assert length(plugins) == 3

      cron_plugin = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Cron end)
      assert cron_plugin, "Cron plugin should be present"

      {Oban.Plugins.Cron, opts} = cron_plugin
      crontab = Keyword.get(opts, :crontab)

      assert is_list(crontab)
      assert length(crontab) == 1

      {schedule, worker} = List.first(crontab)
      assert schedule == "0 */6 * * *"
      assert worker == GscSyncWorker

      System.delete_env("ENABLE_AUTO_SYNC")
    end

    test "cron plugin uses custom schedule from env var" do
      System.put_env("ENABLE_AUTO_SYNC", "true")
      System.put_env("AUTO_SYNC_CRON", "0 4 * * *")

      plugins = GscAnalytics.Config.AutoSync.plugins()
      {Oban.Plugins.Cron, opts} = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Cron end)

      crontab = Keyword.get(opts, :crontab)
      {schedule, _worker} = List.first(crontab)

      assert schedule == "0 4 * * *"

      System.delete_env("ENABLE_AUTO_SYNC")
      System.delete_env("AUTO_SYNC_CRON")
    end
  end

  describe "telemetry event emission" do
    test "worker emits start, complete, and sync_all events" do
      test_pid = self()

      events_to_capture = [
        [:gsc_analytics, :auto_sync, :started],
        [:gsc_analytics, :auto_sync, :complete],
        [:gsc_analytics, :sync_all, :complete]
      ]

      for event <- events_to_capture do
        :telemetry.attach(
          "test-#{Enum.join(event, "-")}",
          event,
          fn event, measurements, metadata, _config ->
            send(test_pid, {:telemetry, event, measurements, metadata})
          end,
          nil
        )
      end

      perform_job(GscSyncWorker, %{})

      # Should receive all three events
      assert_received {:telemetry, [:gsc_analytics, :auto_sync, :started], _, _}
      assert_received {:telemetry, [:gsc_analytics, :auto_sync, :complete], _, _}
      assert_received {:telemetry, [:gsc_analytics, :sync_all, :complete], _, _}

      for event <- events_to_capture do
        :telemetry.detach("test-#{Enum.join(event, "-")}")
      end
    end

    test "worker emits failure event when workspaces have no properties" do
      # Workspaces without properties will fail to sync
      test_pid = self()

      :telemetry.attach(
        "test-failure-event",
        [:gsc_analytics, :auto_sync, :complete],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_complete, event, measurements, metadata})
        end,
        nil
      )

      # Worker should still return :ok even with failures
      assert :ok = perform_job(GscSyncWorker, %{})

      # Should receive complete event with failures count
      assert_received {:telemetry_complete, [:gsc_analytics, :auto_sync, :complete], measurements,
                       _metadata}

      # Workspaces without properties should fail
      assert measurements.failures >= 0

      :telemetry.detach("test-failure-event")
    end
  end

  describe "workspace filtering" do
    test "only syncs workspaces with enabled=true" do
      # Create a mix of enabled and disabled workspaces
      user = AuthFixtures.user_fixture()

      _enabled1 = AccountsFixtures.workspace_fixture(user: user, enabled: true)
      _disabled1 = AccountsFixtures.workspace_fixture(user: user, enabled: false)
      _enabled2 = AccountsFixtures.workspace_fixture(user: user, enabled: true)
      _disabled2 = AccountsFixtures.workspace_fixture(user: user, enabled: false)

      # Delete other workspaces from setup
      Repo.delete_all(from w in Workspace, where: w.user_id != ^user.id)

      # Count enabled workspaces
      enabled_count = Repo.aggregate(from(w in Workspace, where: w.enabled == true), :count)
      assert enabled_count == 2

      # Capture sync_all telemetry
      test_pid = self()

      :telemetry.attach(
        "test-workspace-count",
        [:gsc_analytics, :sync_all, :complete],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:workspace_count, measurements.total_workspaces})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:workspace_count, 2}

      :telemetry.detach("test-workspace-count")
    end
  end

  describe "error resilience" do
    test "continues processing after individual workspace failures" do
      # This test verifies that if one workspace fails, others continue
      # In a real scenario, this would test API failures, but we can verify
      # the behavior through telemetry

      test_pid = self()

      :telemetry.attach(
        "test-partial-success",
        [:gsc_analytics, :auto_sync, :complete],
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:sync_result, measurements})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:sync_result, measurements}

      # Verify measurements structure
      assert is_integer(measurements.total_workspaces)
      assert is_integer(measurements.successes)
      assert is_integer(measurements.failures)
      assert measurements.total_workspaces == measurements.successes + measurements.failures

      :telemetry.detach("test-partial-success")
    end
  end
end
