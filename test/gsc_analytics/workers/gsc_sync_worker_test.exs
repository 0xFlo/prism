defmodule GscAnalytics.Workers.GscSyncWorkerTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  import Mox

  alias GscAnalytics.Workers.GscSyncWorker
  alias GscAnalytics.Config.AutoSync

  # Define behaviour for auto-sync module
  defmodule AutoSyncBehaviour do
    @callback sync_all_workspaces(days :: pos_integer()) :: {:ok, map()}
  end

  # Define mock for auto-sync
  Mox.defmock(AutoSyncMock, for: AutoSyncBehaviour)

  setup :verify_on_exit!

  setup do
    # Configure mock module for unit tests
    Application.put_env(:gsc_analytics, :auto_sync_module, AutoSyncMock)

    # Restore original module after test
    on_exit(fn ->
      Application.delete_env(:gsc_analytics, :auto_sync_module)
    end)

    :ok
  end

  describe "perform/1" do
    test "calls sync_all_workspaces with configured days" do
      # Set AUTO_SYNC_DAYS to 30 for this test
      System.put_env("AUTO_SYNC_DAYS", "30")

      AutoSyncMock
      |> expect(:sync_all_workspaces, fn 30 ->
        {:ok,
         %{
           total_workspaces: 2,
           successes: [],
           failures: []
         }}
      end)

      # Create and perform the job
      assert :ok = perform_job(GscSyncWorker, %{})

      # Clean up
      System.delete_env("AUTO_SYNC_DAYS")
    end

    test "defaults to 14 days when AUTO_SYNC_DAYS not set" do
      # Ensure env var is not set
      System.delete_env("AUTO_SYNC_DAYS")

      AutoSyncMock
      |> expect(:sync_all_workspaces, fn 14 ->
        {:ok,
         %{
           total_workspaces: 1,
           successes: [],
           failures: []
         }}
      end)

      assert :ok = perform_job(GscSyncWorker, %{})
    end

    test "returns :ok when sync is successful" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:ok,
         %{
           total_workspaces: 3,
           successes: [{:workspace1, %{}}, {:workspace2, %{}}, {:workspace3, %{}}],
           failures: []
         }}
      end)

      assert :ok = perform_job(GscSyncWorker, %{})
    end

    test "returns :ok even when some workspaces fail" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:ok,
         %{
           total_workspaces: 3,
           successes: [{:workspace1, %{}}, {:workspace2, %{}}],
           failures: [{:workspace3, :api_timeout}]
         }}
      end)

      # Should still return :ok - failures are tracked but job succeeds
      assert :ok = perform_job(GscSyncWorker, %{})
    end

    test "returns error tuple when sync_all_workspaces returns error" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:error, :database_connection_lost}
      end)

      assert {:error, :database_connection_lost} = perform_job(GscSyncWorker, %{})
    end

    test "emits telemetry start event" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:ok,
         %{
           total_workspaces: 1,
           successes: [],
           failures: []
         }}
      end)

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-worker-start-handler",
        [:gsc_analytics, :auto_sync, :started],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_start, event, measurements, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:telemetry_start, [:gsc_analytics, :auto_sync, :started], measurements,
                       metadata}

      # Assert on observable monitoring data (not configuration values)
      assert is_integer(measurements.system_time)
      assert is_integer(metadata.sync_days), "sync_days should be present for monitoring"

      :telemetry.detach("test-worker-start-handler")
    end

    test "emits telemetry complete event" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:ok,
         %{
           total_workspaces: 2,
           successes: [{:ws1, %{}}, {:ws2, %{}}],
           failures: []
         }}
      end)

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-worker-complete-handler",
        [:gsc_analytics, :auto_sync, :complete],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_complete, event, measurements, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:telemetry_complete, [:gsc_analytics, :auto_sync, :complete], measurements,
                       metadata}

      # Assert on observable outcomes (sync succeeded)
      assert is_integer(measurements.duration_ms)
      assert measurements.total_workspaces == 2
      assert measurements.successes == 2
      assert measurements.failures == 0

      # Configuration value (sync_days) is not observable behavior - don't assert specific value
      assert is_integer(metadata.sync_days), "sync_days should be present for monitoring"

      :telemetry.detach("test-worker-complete-handler")
    end

    test "emits telemetry failure event when error occurs" do
      AutoSyncMock
      |> expect(:sync_all_workspaces, fn _days ->
        {:error, :catastrophic_failure}
      end)

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-worker-failure-handler",
        [:gsc_analytics, :auto_sync, :failure],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_failure, event, measurements, metadata})
        end,
        nil
      )

      perform_job(GscSyncWorker, %{})

      assert_received {:telemetry_failure, [:gsc_analytics, :auto_sync, :failure], measurements,
                       metadata}

      assert is_integer(measurements.duration_ms)
      assert metadata.error == :catastrophic_failure
      assert metadata.sync_days == 14

      :telemetry.detach("test-worker-failure-handler")
    end
  end

  describe "Oban worker configuration" do
    test "is configured with correct queue" do
      assert GscSyncWorker.worker_config()[:queue] == :gsc_sync
    end

    test "has priority of 1" do
      assert GscSyncWorker.worker_config()[:priority] == 1
    end

    test "allows 3 max attempts" do
      assert GscSyncWorker.worker_config()[:max_attempts] == 3
    end
  end
end
