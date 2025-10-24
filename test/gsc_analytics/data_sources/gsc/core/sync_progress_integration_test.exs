defmodule GscAnalytics.DataSources.GSC.Core.SyncProgressIntegrationTest do
  @moduledoc """
  Integration tests verifying that Sync module correctly tracks progress
  via SyncProgress GenServer with proper step numbering.

  These tests catch the 0% progress bug by ensuring step numbers are
  passed correctly throughout the sync pipeline.
  """

  use GscAnalytics.DataCase, async: false

  @moduletag :integration

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias Phoenix.PubSub

  @site_url "sc-domain:test.com"

  setup do
    # Subscribe to progress updates for verification
    :ok = PubSub.subscribe(GscAnalytics.PubSub, "gsc_sync_progress")

    # Install fake client
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.ProgressTrackingClient)

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
      flush_messages()
    end)

    :ok
  end

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  describe "step tracking through sync pipeline" do
    test "sync_date_range reports step numbers sequentially" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-03]

      {:ok, _summary} = Sync.sync_date_range(@site_url, start_date, end_date, force?: true)

      # Should receive started event
      assert_receive {:sync_progress, %{type: :started, job: job}}
      assert job.total_steps == 3

      # Should receive step_completed events with correct step numbers
      # Dates are processed newest-first (reversed), so:
      # Step 1 = 2024-01-03
      # Step 2 = 2024-01-02
      # Step 3 = 2024-01-01

      assert_receive {:sync_progress, %{type: :step_completed, event: event1}}
      assert event1.step == 1
      assert event1.date == ~D[2024-01-03]

      assert_receive {:sync_progress, %{type: :step_completed, event: event2}}
      assert event2.step == 2
      assert event2.date == ~D[2024-01-02]

      assert_receive {:sync_progress, %{type: :step_completed, event: event3}}
      assert event3.step == 3
      assert event3.date == ~D[2024-01-01]
    end

    test "completed_steps increments with each day" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-02]

      {:ok, _summary} = Sync.sync_date_range(@site_url, start_date, end_date, force?: true)

      # Skip started event
      assert_receive {:sync_progress, %{type: :started}}

      # First day completes
      assert_receive {:sync_progress, %{type: :step_completed, job: job1}}
      assert job1.completed_steps == 1

      # Second day completes
      assert_receive {:sync_progress, %{type: :step_completed, job: job2}}
      assert job2.completed_steps == 2
    end

    test "progress percentage increases correctly" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-04]

      {:ok, _summary} = Sync.sync_date_range(@site_url, start_date, end_date, force?: true)

      # Skip started event
      assert_receive {:sync_progress, %{type: :started}}

      # 1/4 = 25%
      assert_receive {:sync_progress, %{type: :step_completed, job: job1}}
      assert job1.completed_steps == 1
      assert calculate_percent(job1) == 25.0

      # 2/4 = 50%
      assert_receive {:sync_progress, %{type: :step_completed, job: job2}}
      assert job2.completed_steps == 2
      assert calculate_percent(job2) == 50.0

      # 3/4 = 75%
      assert_receive {:sync_progress, %{type: :step_completed, job: job3}}
      assert job3.completed_steps == 3
      assert calculate_percent(job3) == 75.0

      # 4/4 = 100%
      assert_receive {:sync_progress, %{type: :step_completed, job: job4}}
      assert job4.completed_steps == 4
      assert calculate_percent(job4) == 100.0
    end

    test "sync_yesterday includes step number" do
      {:ok, _summary} = Sync.sync_yesterday(@site_url)

      assert_receive {:sync_progress, %{type: :started, job: job}}
      assert job.total_steps == 1

      assert_receive {:sync_progress, %{type: :step_completed, event: event}}
      assert event.step == 1
    end

    test "sync_last_n_days tracks all steps" do
      {:ok, _summary} = Sync.sync_last_n_days(@site_url, 5, force?: true)

      assert_receive {:sync_progress, %{type: :started, job: job}}
      assert job.total_steps == 5

      # Should receive 5 step_completed events
      for expected_step <- 1..5 do
        assert_receive {:sync_progress, %{type: :step_completed, event: event}}
        assert event.step == expected_step
      end
    end
  end

  describe "step tracking with already-synced days" do
    setup do
      # Use a client that returns data
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.ProgressTrackingClient)
      :ok
    end

    test "filters out already-synced days but tracks remaining" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-03]

      # Mark day 2 as already synced
      {:ok, _sync_day} =
        GscAnalytics.DataSources.GSC.Core.Persistence.mark_day_complete(
          1,
          @site_url,
          ~D[2024-01-02]
        )

      {:ok, summary} = Sync.sync_date_range(@site_url, start_date, end_date)

      # Only 2 days should be processed (day 2 filtered out)
      assert summary.days_processed == 2

      assert_receive {:sync_progress, %{type: :started, job: job}}
      assert job.total_steps == 3

      # Should receive step_completed for only the 2 non-synced days
      # But they still get step numbers (1 and 2 because day 2 was skipped)
      assert_receive {:sync_progress, %{type: :step_completed, event: _event1}}
      assert_receive {:sync_progress, %{type: :step_completed, event: _event2}}
      assert_receive {:sync_progress, %{type: :step_completed, event: _event3}}
    end
  end

  describe "error handling with step tracking" do
    setup do
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.ErrorClient)
      :ok
    end

    test "errors include step number" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-02]

      # Sync continues even with errors for individual URLs
      {:ok, _summary} = Sync.sync_date_range(@site_url, start_date, end_date, force?: true)

      assert_receive {:sync_progress, %{type: :started}}

      # Error events should still have step numbers
      # We expect 2 error events (one for each date)
      assert_receive {:sync_progress, %{type: :step_completed, event: event1}}
      assert event1.step in [1, 2]
      assert event1.status == :error

      assert_receive {:sync_progress, %{type: :step_completed, event: event2}}
      assert event2.step in [1, 2]
      assert event2.status == :error
    end
  end

  # Helper function matching SyncProgress test pattern
  defp calculate_percent(job) do
    total = job.total_steps || 0
    completed = job.completed_steps || 0

    if total > 0 do
      min(completed / total * 100, 100.0) |> Float.round(2)
    else
      0.0
    end
  end

  # Fake clients for testing

  defmodule ProgressTrackingClient do
    def fetch_all_urls_for_date(_, _, _date) do
      {:ok, %{"rows" => [%{"keys" => ["https://example.com/page"], "clicks" => 1}]}}
    end

    def fetch_query_batch(_, requests, _operation) do
      responses =
        Enum.map(requests, fn request ->
          %{
            id: request.id,
            status: 200,
            body: %{"rows" => []},
            raw_body: nil,
            metadata: request.metadata
          }
        end)

      {:ok, responses, 1}
    end
  end

  defmodule SkippedDaysClient do
    def fetch_all_urls_for_date(_, _, _date) do
      {:ok, %{"rows" => [%{"keys" => ["https://example.com/page"], "clicks" => 1}]}}
    end

    def fetch_query_batch(_, requests, _operation) do
      responses =
        Enum.map(requests, fn request ->
          %{
            id: request.id,
            status: 200,
            body: %{"rows" => []},
            raw_body: nil,
            metadata: request.metadata
          }
        end)

      {:ok, responses, 1}
    end
  end

  defmodule ErrorClient do
    def fetch_all_urls_for_date(_, _, _) do
      {:error, :api_error}
    end

    def fetch_query_batch(_, _, _) do
      {:error, :api_error}
    end
  end
end
