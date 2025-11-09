defmodule GscAnalytics.DataSources.GSC.Core.SyncAllTest do
  use GscAnalytics.DataCase, async: true

  import Mox
  import Ecto.Query

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.AuthFixtures
  alias GscAnalytics.AccountsFixtures

  # Define behaviour for workspace sync runner
  defmodule WorkspaceSyncBehaviour do
    @callback sync_workspace(
                workspace :: %GscAnalytics.Schemas.Workspace{},
                days :: pos_integer()
              ) ::
                {:ok, map()} | {:error, any()}
  end

  # Define mock for workspace sync
  Mox.defmock(WorkspaceSyncMock, for: WorkspaceSyncBehaviour)

  setup :verify_on_exit!

  describe "sync_all_workspaces/1" do
    setup do
      # Create users
      user1 = AuthFixtures.user_fixture()
      user2 = AuthFixtures.user_fixture()

      # Create workspaces with different states
      enabled_ws1 = AccountsFixtures.workspace_fixture(user: user1, enabled: true)
      enabled_ws2 = AccountsFixtures.workspace_fixture(user: user2, enabled: true)
      disabled_ws = AccountsFixtures.workspace_fixture(user: user1, enabled: false)

      %{
        user1: user1,
        user2: user2,
        enabled_ws1: enabled_ws1,
        enabled_ws2: enabled_ws2,
        disabled_ws: disabled_ws
      }
    end

    test "syncs all enabled workspaces across all users", %{
      enabled_ws1: ws1,
      enabled_ws2: ws2
    } do
      # Configure mock runner
      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      # Expect sync to be called for each enabled workspace
      WorkspaceSyncMock
      |> expect(:sync_workspace, fn workspace, 14 ->
        assert workspace.id in [ws1.id, ws2.id]
        assert workspace.enabled == true
        {:ok, %{urls_synced: 100, queries_synced: 50}}
      end)
      |> expect(:sync_workspace, fn workspace, 14 ->
        assert workspace.id in [ws1.id, ws2.id]
        assert workspace.enabled == true
        {:ok, %{urls_synced: 75, queries_synced: 30}}
      end)

      {:ok, result} = Sync.sync_all_workspaces(14)

      assert result.total_workspaces == 2
      assert length(result.successes) == 2
      assert length(result.failures) == 0
    end

    test "does not sync disabled workspaces" do
      # Create a fresh set of workspaces for this test only
      user = AuthFixtures.user_fixture()
      enabled_ws = AccountsFixtures.workspace_fixture(user: user, enabled: true)
      _disabled_ws = AccountsFixtures.workspace_fixture(user: user, enabled: false)

      # Delete any other enabled workspaces from the setup
      GscAnalytics.Repo.delete_all(
        from w in GscAnalytics.Schemas.Workspace,
          where: w.id != ^enabled_ws.id and w.enabled == true
      )

      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      # Should only be called once for the enabled workspace
      WorkspaceSyncMock
      |> expect(:sync_workspace, 1, fn workspace, 14 ->
        assert workspace.id == enabled_ws.id
        {:ok, %{urls_synced: 100}}
      end)

      {:ok, result} = Sync.sync_all_workspaces(14)

      # Only 1 enabled workspace, disabled workspace should be skipped
      assert result.total_workspaces == 1
    end

    test "handles workspace sync failures gracefully", %{enabled_ws1: ws1, enabled_ws2: ws2} do
      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      # First workspace succeeds, second fails
      WorkspaceSyncMock
      |> expect(:sync_workspace, fn workspace, 14 ->
        if workspace.id == ws1.id do
          {:ok, %{urls_synced: 100}}
        else
          {:error, :api_timeout}
        end
      end)
      |> expect(:sync_workspace, fn workspace, 14 ->
        if workspace.id == ws2.id do
          {:error, :api_timeout}
        else
          {:ok, %{urls_synced: 100}}
        end
      end)

      {:ok, result} = Sync.sync_all_workspaces(14)

      assert result.total_workspaces == 2
      assert length(result.successes) == 1
      assert length(result.failures) == 1

      # Verify failure details
      {failed_workspace, reason} = List.first(result.failures)
      assert failed_workspace.id == ws2.id
      assert reason == :api_timeout
    end

    test "returns empty result when no enabled workspaces exist" do
      # Delete all workspaces
      Repo.delete_all(GscAnalytics.Schemas.Workspace)

      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      # Should not call sync at all
      {:ok, result} = Sync.sync_all_workspaces(14)

      assert result.total_workspaces == 0
      assert result.successes == []
      assert result.failures == []
    end

    test "uses configured sync days parameter" do
      # Create a fresh workspace
      user = AuthFixtures.user_fixture()
      ws = AccountsFixtures.workspace_fixture(user: user, enabled: true)

      # Delete other enabled workspaces
      GscAnalytics.Repo.delete_all(
        from w in GscAnalytics.Schemas.Workspace,
          where: w.id != ^ws.id and w.enabled == true
      )

      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      WorkspaceSyncMock
      |> expect(:sync_workspace, fn workspace, 30 ->
        assert workspace.id == ws.id
        {:ok, %{urls_synced: 100}}
      end)

      {:ok, result} = Sync.sync_all_workspaces(30)

      assert result.total_workspaces == 1
    end

    test "emits telemetry events for sync operations" do
      # Create a fresh workspace
      user = AuthFixtures.user_fixture()
      ws = AccountsFixtures.workspace_fixture(user: user, enabled: true)

      # Delete other enabled workspaces
      GscAnalytics.Repo.delete_all(
        from w in GscAnalytics.Schemas.Workspace,
          where: w.id != ^ws.id and w.enabled == true
      )

      Application.put_env(:gsc_analytics, :workspace_sync_runner, WorkspaceSyncMock)

      WorkspaceSyncMock
      |> expect(:sync_workspace, fn workspace, _days ->
        assert workspace.id == ws.id
        {:ok, %{urls_synced: 100}}
      end)

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-sync-all-handler",
        [:gsc_analytics, :sync_all, :complete],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _result} = Sync.sync_all_workspaces(14)

      assert_received {:telemetry_event, [:gsc_analytics, :sync_all, :complete], measurements,
                       metadata}

      assert is_integer(measurements.duration_ms)
      assert measurements.total_workspaces == 1
      assert measurements.successes == 1
      assert measurements.failures == 0
      assert metadata.sync_days == 14

      :telemetry.detach("test-sync-all-handler")
    end
  end
end
