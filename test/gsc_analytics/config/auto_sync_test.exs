defmodule GscAnalytics.Config.AutoSyncTest do
  use ExUnit.Case, async: false

  alias GscAnalytics.Config.AutoSync

  # Helper to safely manipulate environment variables in tests
  defp with_env(env_map, fun) do
    original_env =
      Enum.map(env_map, fn {key, _value} ->
        {key, System.get_env(key)}
      end)

    try do
      Enum.each(env_map, fn {key, value} ->
        if value do
          System.put_env(key, value)
        else
          System.delete_env(key)
        end
      end)

      fun.()
    after
      Enum.each(original_env, fn {key, original_value} ->
        if original_value do
          System.put_env(key, original_value)
        else
          System.delete_env(key)
        end
      end)
    end
  end

  describe "enabled?/0" do
    test "returns false when ENABLE_AUTO_SYNC is not set" do
      with_env(%{"ENABLE_AUTO_SYNC" => nil}, fn ->
        refute AutoSync.enabled?()
      end)
    end

    test "returns false when ENABLE_AUTO_SYNC is set to false" do
      with_env(%{"ENABLE_AUTO_SYNC" => "false"}, fn ->
        refute AutoSync.enabled?()
      end)
    end

    test "returns false when ENABLE_AUTO_SYNC is set to 0" do
      with_env(%{"ENABLE_AUTO_SYNC" => "0"}, fn ->
        refute AutoSync.enabled?()
      end)
    end

    test "returns true when ENABLE_AUTO_SYNC is set to true" do
      with_env(%{"ENABLE_AUTO_SYNC" => "true"}, fn ->
        assert AutoSync.enabled?()
      end)
    end

    test "returns true when ENABLE_AUTO_SYNC is set to 1" do
      with_env(%{"ENABLE_AUTO_SYNC" => "1"}, fn ->
        assert AutoSync.enabled?()
      end)
    end
  end

  describe "sync_days/0" do
    test "returns 14 by default when AUTO_SYNC_DAYS is not set" do
      with_env(%{"AUTO_SYNC_DAYS" => nil}, fn ->
        assert AutoSync.sync_days() == 14
      end)
    end

    test "returns the configured value when AUTO_SYNC_DAYS is set" do
      with_env(%{"AUTO_SYNC_DAYS" => "30"}, fn ->
        assert AutoSync.sync_days() == 30
      end)
    end

    test "returns 14 when AUTO_SYNC_DAYS is invalid" do
      with_env(%{"AUTO_SYNC_DAYS" => "invalid"}, fn ->
        assert AutoSync.sync_days() == 14
      end)
    end

    test "returns 14 when AUTO_SYNC_DAYS is negative" do
      with_env(%{"AUTO_SYNC_DAYS" => "-5"}, fn ->
        assert AutoSync.sync_days() == 14
      end)
    end
  end

  describe "cron_schedule/0" do
    test "returns default schedule when AUTO_SYNC_CRON is not set" do
      with_env(%{"AUTO_SYNC_CRON" => nil}, fn ->
        assert AutoSync.cron_schedule() == "0 */6 * * *"
      end)
    end

    test "returns the configured schedule when AUTO_SYNC_CRON is set" do
      with_env(%{"AUTO_SYNC_CRON" => "0 4 * * *"}, fn ->
        assert AutoSync.cron_schedule() == "0 4 * * *"
      end)
    end
  end

  describe "plugins/0" do
    test "background jobs run when auto-sync is disabled" do
      with_env(%{"ENABLE_AUTO_SYNC" => "false"}, fn ->
        plugins = AutoSync.plugins()

        # Assert on observable behavior: required plugins are present
        pruner = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Pruner end)
        cron = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Cron end)

        assert pruner, "Pruner plugin should be present for job cleanup"
        assert cron, "Cron plugin should be present for scheduled jobs"

        # Verify background jobs are scheduled (SERP pruning + HTTP rechecking)
        {Oban.Plugins.Cron, opts} = cron
        crontab = Keyword.get(opts, :crontab)

        # Assert: SERP pruning job exists
        assert Enum.any?(crontab, fn {_sched, worker} ->
                 worker == GscAnalytics.Workers.SerpPruningWorker
               end),
               "SERP pruning should be scheduled"

        # Assert: HTTP status rechecking job exists
        assert Enum.any?(crontab, fn {_sched, worker} ->
                 worker == GscAnalytics.Workers.HttpStatusRecheckWorker
               end),
               "HTTP status rechecking should be scheduled"

        # Assert: GSC sync job NOT scheduled when auto-sync disabled
        refute Enum.any?(crontab, fn {_sched, worker} ->
                 worker == GscAnalytics.Workers.GscSyncWorker
               end),
               "GSC sync should NOT run when auto-sync disabled"
      end)
    end

    test "all required plugins are enabled when auto-sync is enabled" do
      with_env(%{"ENABLE_AUTO_SYNC" => "true"}, fn ->
        plugins = AutoSync.plugins()

        # Assert on observable behavior: required plugins are present
        pruner = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Pruner end)
        lifeline = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Lifeline end)
        cron = Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Cron end)

        assert pruner, "Pruner plugin required for job cleanup"
        assert lifeline, "Lifeline plugin required for orphaned job recovery"
        assert cron, "Cron plugin required for scheduled syncs"
      end)
    end

    test "GSC sync uses configured schedule when auto-sync is enabled" do
      with_env(%{"ENABLE_AUTO_SYNC" => "true", "AUTO_SYNC_CRON" => "0 4 * * *"}, fn ->
        plugins = AutoSync.plugins()

        {Oban.Plugins.Cron, opts} =
          Enum.find(plugins, fn {mod, _} -> mod == Oban.Plugins.Cron end)

        crontab = Keyword.get(opts, :crontab)
        assert is_list(crontab)

        # Find the GSC sync job
        gsc_sync_job =
          Enum.find(crontab, fn {_sched, worker} ->
            worker == GscAnalytics.Workers.GscSyncWorker
          end)

        assert {schedule, worker_module} = gsc_sync_job
        assert schedule == "0 4 * * *"
        assert worker_module == GscAnalytics.Workers.GscSyncWorker

        # Verify SERP pruning job is also present
        serp_prune_job =
          Enum.find(crontab, fn {_sched, worker} ->
            worker == GscAnalytics.Workers.SerpPruningWorker
          end)

        assert {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker} = serp_prune_job
      end)
    end
  end

  describe "log_status!/0" do
    test "executes without error when auto-sync is disabled" do
      with_env(%{"ENABLE_AUTO_SYNC" => "false"}, fn ->
        assert :ok = AutoSync.log_status!()
      end)
    end

    test "executes without error when auto-sync is enabled" do
      with_env(
        %{
          "ENABLE_AUTO_SYNC" => "true",
          "AUTO_SYNC_DAYS" => "14",
          "AUTO_SYNC_CRON" => "0 */6 * * *"
        },
        fn ->
          assert :ok = AutoSync.log_status!()
        end
      )
    end
  end
end
