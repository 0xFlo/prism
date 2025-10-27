defmodule GscAnalytics.DataSources.GSC.SyncJourneyIntegrationTest do
  @moduledoc """
  Integration tests for GSC sync user journeys.

  Tests the complete sync experience from the perspective of business requirements:
  - System syncs GSC data successfully
  - Progress tracking works in real-time
  - Error handling and recovery
  - Sync status reporting

  Following testing guidelines:
  - Test behavior, not implementation
  - Assert on observable outcomes (database, PubSub)
  - Tests survive refactoring
  """

  use GscAnalytics.DataCase, async: false

  @moduletag :integration

  alias GscAnalytics.DataSources.GSC.Core.Sync
  alias GscAnalytics.DataSources.GSC.Support.SyncProgress
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.{TimeSeries, SyncDay}

  import Ecto.Query

  @site_url "sc-domain:test.com"
  @account_id 1

  setup do
    # Set up fake client that returns predictable data
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.FakeSyncClient)

    # Subscribe to progress updates
    SyncProgress.subscribe()

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
    end)

    :ok
  end

  describe "basic sync journey: data appears in database" do
    test "user syncs single day and sees data in TimeSeries" do
      # Business requirement: "Users can sync GSC data for specific dates"

      # Action: Sync a single day
      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15],
                 account_id: @account_id
               )

      # Assert: Sync reports success
      assert summary.total_urls > 0
      assert summary.days_processed == 1

      # Assert: Data appears in database (observable outcome)
      date = ~D[2025-10-15]

      time_series_records =
        Repo.all(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^date
        )

      assert length(time_series_records) > 0

      # Assert: Each record has required metrics
      for record <- time_series_records do
        assert record.url != nil
        assert record.clicks >= 0
        assert record.impressions >= 0
        assert record.ctr >= 0.0
        assert record.position >= 0.0
      end
    end

    test "user syncs multiple days and sees all data" do
      # Business requirement: "Users can sync date ranges"

      # Action: Sync 5 days
      start_date = ~D[2025-10-10]
      end_date = ~D[2025-10-14]

      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, start_date, end_date, account_id: @account_id)

      # Assert: Summary shows all days completed
      assert summary.days_processed == 5

      # Assert: Database has data for each day
      for date <- Date.range(start_date, end_date) do
        count =
          Repo.one!(
            from ts in TimeSeries,
              where: ts.account_id == ^@account_id and ts.date == ^date,
              select: count()
          )

        assert count > 0, "Should have data for #{date}"
      end
    end

    test "user syncs URLs with top queries data" do
      # Business requirement: "System stores search queries that drive traffic to URLs"

      # Action: Sync data that includes top queries
      assert {:ok, _summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15],
                 account_id: @account_id
               )

      # Assert: Some TimeSeries records have top_queries data
      date = ~D[2025-10-15]

      records_with_queries =
        Repo.all(
          from ts in TimeSeries,
            where:
              ts.account_id == ^@account_id and
                ts.date == ^date and
                not is_nil(ts.top_queries)
        )

      assert length(records_with_queries) > 0

      # Assert: Query data has expected structure
      [record | _] = records_with_queries
      assert is_list(record.top_queries)

      for query <- record.top_queries do
        assert is_map(query)
        assert query["query"] != nil
        assert query["clicks"] >= 0
        assert query["impressions"] >= 0
      end
    end
  end

  describe "sync status tracking journey" do
    test "user can see which days completed successfully" do
      # Business requirement: "System tracks sync completion status per day"

      # Action: Sync multiple days
      assert {:ok, _summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-10], ~D[2025-10-12],
                 account_id: @account_id
               )

      # Assert: SyncDay records show completion status
      start_date = ~D[2025-10-10]
      end_date = ~D[2025-10-12]

      sync_days =
        Repo.all(
          from sd in SyncDay,
            where:
              sd.account_id == ^@account_id and
                sd.site_url == ^@site_url and
                sd.date >= ^start_date and
                sd.date <= ^end_date,
            order_by: sd.date
        )

      assert length(sync_days) == 3

      # Each day should be marked complete
      for sync_day <- sync_days do
        assert sync_day.status == :complete
      end

      # Verify actual data in TimeSeries (observable outcome)
      for date <- Date.range(start_date, end_date) do
        count =
          Repo.one!(
            from ts in TimeSeries,
              where: ts.account_id == ^@account_id and ts.date == ^date,
              select: count()
          )

        assert count > 0, "Should have TimeSeries data for #{date}"
      end
    end

    test "user can distinguish between data and no-data days" do
      # Business requirement: "System distinguishes between no data vs data available"

      # Setup: Configure client to return no data for specific date
      Application.put_env(:gsc_analytics, :test_no_data_dates, [~D[2025-10-11]])

      on_exit(fn ->
        Application.delete_env(:gsc_analytics, :test_no_data_dates)
      end)

      # Action: Sync range including no-data day
      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-10], ~D[2025-10-12],
                 account_id: @account_id
               )

      # Assert: Sync completes without error
      assert summary.days_processed == 3

      # Assert: System can distinguish between data and no-data days
      no_data_date = ~D[2025-10-11]
      data_date = ~D[2025-10-10]

      # Check TimeSeries records directly (observable database state)
      no_data_count =
        Repo.one!(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^no_data_date,
            select: count()
        )

      data_count =
        Repo.one!(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^data_date,
            select: count()
        )

      # No-data day should have no TimeSeries records
      assert no_data_count == 0

      # Data day should have TimeSeries records
      assert data_count > 0
    end
  end

  describe "progress tracking journey: real-time updates" do
    test "user receives progress updates via PubSub during sync" do
      # Business requirement: "Users see real-time sync progress"

      # Action: Start sync in background task to monitor progress
      task =
        Task.async(fn ->
          Sync.sync_date_range(@site_url, ~D[2025-10-10], ~D[2025-10-14], account_id: @account_id)
        end)

      # Assert: Receive progress updates (observable via PubSub)
      # First message should be :started event
      assert_receive {:sync_progress, %{type: :started, job: job}}, 5_000

      assert job.metadata.site_url == @site_url
      assert job.total_steps == 5
      assert job.completed_steps == 0

      # Wait for sync to complete
      assert {:ok, {:ok, _summary}} = Task.yield(task, 10_000)
    end

    test "user sees step completion notifications" do
      # Business requirement: "System notifies as each day completes"

      # Action: Sync data
      task =
        Task.async(fn ->
          Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15], account_id: @account_id)
        end)

      # Assert: Receive started notification
      assert_receive {:sync_progress, %{type: :started}}, 1_000

      # Assert: Receive step completion notification
      assert_receive {:sync_progress, %{type: :step_completed, job: job}}, 5_000

      assert job.completed_steps == 1
      assert job.total_steps == 1

      # Wait for task to complete
      Task.await(task, 5_000)
    end

    test "progress updates show increasing completion" do
      # Business requirement: "Progress increases as sync proceeds"

      # Action: Sync multiple days
      task =
        Task.async(fn ->
          Sync.sync_date_range(@site_url, ~D[2025-10-01], ~D[2025-10-05], account_id: @account_id)
        end)

      # Skip started event
      assert_receive {:sync_progress, %{type: :started}}

      # Collect completed_steps values
      completed_values =
        for _ <- 1..5 do
          assert_receive {:sync_progress, %{type: :step_completed, job: job}}, 5_000
          job.completed_steps
        end

      # Assert: Values increase from 1 to 5
      assert completed_values == [1, 2, 3, 4, 5]

      # Wait for task
      Task.await(task, 5_000)
    end
  end

  describe "error handling journey" do
    test "sync continues gracefully when API fails for a day" do
      # Business requirement: "System handles API failures without crashing"

      # Setup: Configure client to return errors
      Application.put_env(:gsc_analytics, :test_error_dates, [~D[2025-10-15]])

      on_exit(fn ->
        Application.delete_env(:gsc_analytics, :test_error_dates)
      end)

      # Action: Attempt sync
      result =
        Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15], account_id: @account_id)

      # Assert: Sync completes but reports 0 URLs for failed day
      assert {:ok, summary} = result
      assert summary.total_urls == 0
      assert summary.days_processed == 1
    end

    test "partial sync saves successfully completed days" do
      # Business requirement: "Partial failures don't lose successfully synced data"

      # Setup: Error on last date only
      Application.put_env(:gsc_analytics, :test_error_dates, [~D[2025-10-12]])

      on_exit(fn ->
        Application.delete_env(:gsc_analytics, :test_error_dates)
      end)

      # Action: Sync range with one failing day
      # Note: This may return error for the failed day, but should still save good days
      Sync.sync_date_range(@site_url, ~D[2025-10-10], ~D[2025-10-12], account_id: @account_id)

      # Assert: Successfully synced days are in database
      start_date = ~D[2025-10-10]
      end_date = ~D[2025-10-12]

      successful_day_count =
        Repo.one!(
          from sd in SyncDay,
            where:
              sd.account_id == ^@account_id and
                sd.status == :complete and
                sd.date >= ^start_date and
                sd.date < ^end_date,
            select: count()
        )

      assert successful_day_count >= 2, "Should save days before error"
    end
  end

  describe "data quality journey" do
    test "synced data matches GSC API response structure" do
      # Business requirement: "Synced data accurately represents GSC metrics"

      # Action: Sync data
      assert {:ok, _summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15],
                 account_id: @account_id
               )

      # Assert: TimeSeries records have valid GSC metric ranges
      date = ~D[2025-10-15]

      records =
        Repo.all(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^date
        )

      for record <- records do
        # CTR should be clicks/impressions
        expected_ctr =
          if record.impressions > 0, do: record.clicks / record.impressions, else: 0.0

        assert_in_delta record.ctr, expected_ctr, 0.001

        # Position should be 0-100 (GSC range, 0 means no data)
        assert record.position >= 0.0
        assert record.position <= 100.0

        # Clicks <= Impressions (always true for GSC data)
        assert record.clicks <= record.impressions
      end
    end

    test "re-syncing same date doesn't duplicate data" do
      # Business requirement: "Re-syncing refreshes data without duplicates"

      # Action: Sync once
      assert {:ok, _first_summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15],
                 account_id: @account_id
               )

      # Get database count after first sync
      date = ~D[2025-10-15]

      first_db_count =
        Repo.one!(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^date,
            select: count()
        )

      assert first_db_count > 0, "First sync should create records"

      # Action: Sync again (same date)
      assert {:ok, _second_summary} =
               Sync.sync_date_range(@site_url, ~D[2025-10-15], ~D[2025-10-15],
                 account_id: @account_id
               )

      # Assert: Record count doesn't double (upsert, not duplicate insert)
      second_db_count =
        Repo.one!(
          from ts in TimeSeries,
            where: ts.account_id == ^@account_id and ts.date == ^date,
            select: count()
        )

      # Should not have doubled the records
      assert second_db_count <= first_db_count * 1.1,
             "Re-sync created duplicates: #{second_db_count} vs #{first_db_count}"
    end
  end

  # Fake GSC client for testing

  defmodule FakeSyncClient do
    @moduledoc """
    Fake GSC client that returns predictable test data.
    """

    def fetch_all_urls_for_date(_account_id, _site_url, date, _opts \\ []) do
      # Check if this date should return an error
      if date in (Application.get_env(:gsc_analytics, :test_error_dates) || []) do
        {:error, :api_error}
      else
        # Check if this date should return no data
        if date in (Application.get_env(:gsc_analytics, :test_no_data_dates) || []) do
          {:ok, %{"rows" => []}}
        else
          # Return normal test data
          rows = generate_url_rows(date)
          {:ok, %{"rows" => rows}}
        end
      end
    end

    def fetch_query_batch(_account_id, requests, _operation) do
      # Return query data for each request
      responses =
        Enum.map(requests, fn request ->
          date = request.metadata.date
          url = extract_url_from_request(request)

          # Check if this date should error
          if date in (Application.get_env(:gsc_analytics, :test_error_dates) || []) do
            %{
              id: request.id,
              status: 500,
              body: nil,
              raw_body: nil,
              metadata: request.metadata
            }
          else
            # Return query data
            rows = generate_query_rows(url, date)

            %{
              id: request.id,
              status: 200,
              body: %{"rows" => rows},
              raw_body: nil,
              metadata: request.metadata
            }
          end
        end)

      {:ok, responses, 1}
    end

    defp extract_url_from_request(request) do
      # Extract URL from request body
      case request.body["dimensionFilterGroups"] do
        [%{"filters" => [%{"dimension" => "page", "expression" => url}]}] -> url
        _ -> "https://test.com/unknown"
      end
    end

    defp generate_url_rows(date) do
      # Generate 10 URLs per date for testing
      day_offset = Date.diff(date, ~D[2025-01-01])

      for i <- 1..10 do
        url_num = day_offset * 10 + i

        %{
          "keys" => ["https://test.com/page-#{url_num}"],
          "clicks" => 50 + rem(url_num, 100),
          "impressions" => 500 + rem(url_num, 1000),
          "ctr" => (50 + rem(url_num, 100)) / (500 + rem(url_num, 1000)),
          "position" => 5.0 + rem(url_num, 50)
        }
      end
    end

    defp generate_query_rows(url, _date) do
      # Extract page number from URL to make queries consistent
      url_hash = :erlang.phash2(url, 100)

      for i <- 1..5 do
        clicks = rem(url_hash + i * 10, 50)
        impressions = rem(url_hash + i * 100, 500) + 100

        %{
          "keys" => [url, "query #{url_hash + i}"],
          "clicks" => clicks,
          "impressions" => impressions,
          "ctr" => clicks / impressions,
          "position" => 5.0 + rem(url_hash + i, 20)
        }
      end
    end
  end
end
