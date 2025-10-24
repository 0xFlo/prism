defmodule GscAnalytics.DataSources.GSC.Core.SyncTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.DataSources.GSC.Core.Sync

  @site_url "sc-domain:test.com"

  setup do
    original_client = Application.get_env(:gsc_analytics, :gsc_client)
    original_pid = Application.get_env(:gsc_analytics, :fake_client_pid)

    on_exit(fn ->
      Application.put_env(:gsc_analytics, :gsc_client, original_client)
      Application.put_env(:gsc_analytics, :fake_client_pid, original_pid)
    end)

    :ok
  end

  describe "error propagation" do
    setup do
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.ErrorClient)
      :ok
    end

    test "sync_yesterday bubbles query batch errors" do
      assert {:error, :boom, %{url_count: 0, api_calls: 1}} =
               Sync.sync_yesterday(@site_url, account_id: 123)
    end
  end

  describe "backfill direction" do
    test "leading empty grace protects older data discovery" do
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.BackfillGraceClient)

      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-06]

      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, start_date, end_date,
                 stop_on_empty?: true,
                 empty_threshold: 2,
                 leading_empty_grace_days: 5
               )

      assert summary[:halt_reason] == nil
      assert summary[:days_processed] == 6
      assert summary[:total_urls] == 1
    end

    test "empty threshold still halts once data seen" do
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.BackfillHaltClient)

      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-05]

      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, start_date, end_date,
                 stop_on_empty?: true,
                 empty_threshold: 2,
                 leading_empty_grace_days: 2
               )

      assert summary[:halt_reason] == :empty_threshold
      assert summary[:halt_on] == ~D[2024-01-03]
      assert summary[:days_processed] == 3
      assert summary[:total_urls] == 1
    end
  end

  describe "multi-date batching" do
    setup do
      original_sync_config =
        Application.get_env(:gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config, [])

      Application.put_env(:gsc_analytics, :fake_client_pid, self())
      Application.put_env(:gsc_analytics, :gsc_client, __MODULE__.MultiSchedulerClient)

      new_config =
        original_sync_config
        |> Keyword.put(:query_batch_pages, 2)
        |> Keyword.put(:query_scheduler_chunk_size, 2)

      Application.put_env(:gsc_analytics, GscAnalytics.DataSources.GSC.Core.Config, new_config)

      on_exit(fn ->
        Application.put_env(
          :gsc_analytics,
          GscAnalytics.DataSources.GSC.Core.Config,
          original_sync_config
        )
      end)

      :ok
    end

    test "sync_date_range batches query pages across dates" do
      start_date = ~D[2024-01-01]
      end_date = ~D[2024-01-02]

      assert {:ok, summary} =
               Sync.sync_date_range(@site_url, start_date, end_date,
                 force?: true,
                 stop_on_empty?: false
               )

      assert summary[:days_processed] == 2
      assert summary[:total_urls] == 3
      assert summary[:halt_reason] == nil

      # With the refactored architecture, we expect:
      # 1. URL batch for both dates
      # 2. Query batch for both dates (initial)
      # 3. Query pagination batch for 2024-01-02

      # First batch: URL fetching
      assert_receive {:batch, url_batch}
      assert Enum.sort(url_batch) == Enum.sort([{~D[2024-01-02], 0}, {~D[2024-01-01], 0}])

      # Second batch: Query fetching (initial)
      assert_receive {:batch, query_batch1}
      assert Enum.sort(query_batch1) == Enum.sort([{~D[2024-01-02], 0}, {~D[2024-01-01], 0}])

      # Third batch: Query pagination for 2024-01-02
      assert_receive {:batch, query_batch2}
      assert query_batch2 == [{~D[2024-01-02], 25_000}]

      # No more batches
      refute_receive {:batch, _}
    end
  end

  defmodule ErrorClient do
    def fetch_all_urls_for_date(_, _, _), do: {:ok, %{"rows" => []}}
    def fetch_query_batch(_, _, _), do: {:error, :boom}
  end

  defmodule BackfillGraceClient do
    def fetch_all_urls_for_date(_, _, date) do
      rows =
        case date do
          ~D[2024-01-02] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
          _ -> []
        end

      {:ok, %{"rows" => rows}}
    end

    def fetch_query_batch(_, requests, operation) do
      responses =
        Enum.map(requests, fn request ->
          # Parse the date from the request ID
          [date_str | _] = String.split(request.id, ":")
          date = Date.from_iso8601!(date_str)

          # For URL fetching (dimensions: ["page"]), return URL data
          # For query fetching (dimensions: ["page", "query"]), return empty
          rows =
            if operation == "fetch_all_urls_batch" do
              case date do
                ~D[2024-01-02] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
                _ -> []
              end
            else
              []
            end

          %{
            id: request.id,
            status: 200,
            body: %{"rows" => rows},
            raw_body: nil,
            metadata: request.metadata
          }
        end)

      {:ok, responses, 1}
    end
  end

  defmodule BackfillHaltClient do
    def fetch_all_urls_for_date(_, _, date) do
      rows =
        case date do
          ~D[2024-01-05] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
          _ -> []
        end

      {:ok, %{"rows" => rows}}
    end

    def fetch_query_batch(_, requests, operation) do
      responses =
        Enum.map(requests, fn request ->
          # Parse the date from the request ID
          [date_str | _] = String.split(request.id, ":")
          date = Date.from_iso8601!(date_str)

          # For URL fetching (dimensions: ["page"]), return URL data
          # For query fetching (dimensions: ["page", "query"]), return empty
          rows =
            if operation == "fetch_all_urls_batch" do
              case date do
                ~D[2024-01-05] -> [%{"keys" => ["https://example.com/page"], "clicks" => 1}]
                _ -> []
              end
            else
              []
            end

          %{
            id: request.id,
            status: 200,
            body: %{"rows" => rows},
            raw_body: nil,
            metadata: request.metadata
          }
        end)

      {:ok, responses, 1}
    end
  end

  defmodule MultiSchedulerClient do
    def fetch_all_urls_for_date(_, _, date) do
      rows =
        case date do
          ~D[2024-01-02] ->
            [
              %{"keys" => ["https://example.com/page"], "clicks" => 1},
              %{"keys" => ["https://example.com/page2"], "clicks" => 1}
            ]

          ~D[2024-01-01] ->
            [%{"keys" => ["https://example.com/page"], "clicks" => 1}]

          _ ->
            []
        end

      {:ok, %{"rows" => rows}}
    end

    def fetch_query_batch(_account_id, requests, operation) do
      send(
        Application.get_env(:gsc_analytics, :fake_client_pid),
        {:batch, Enum.map(requests, &extract_request/1)}
      )

      responses = Enum.map(requests, &build_response(&1, operation))
      {:ok, responses, 1}
    end

    def fetch_all_queries_for_date(_, _, _, _), do: {:ok, %{"rows" => []}}
    def fetch_query_pages_batch(_, _, _, _), do: {:ok, []}

    defp extract_request(request) do
      {date, start_row} = parse_id(request.id)
      {date, start_row}
    end

    defp build_response(request, operation) do
      {date, start_row} = parse_id(request.id)

      rows =
        if operation == "fetch_all_urls_batch" do
          # Return URL data when fetching URLs
          case date do
            ~D[2024-01-02] ->
              [
                %{"keys" => ["https://example.com/page"], "clicks" => 1},
                %{"keys" => ["https://example.com/page2"], "clicks" => 1}
              ]

            ~D[2024-01-01] ->
              [%{"keys" => ["https://example.com/page"], "clicks" => 1}]

            _ ->
              []
          end
        else
          # Return query data when fetching queries
          case {date, start_row} do
            # GSC page size
            {~D[2024-01-02], 0} -> duplicate_rows(25_000)
            {~D[2024-01-02], 25_000} -> duplicate_rows(5_000)
            {~D[2024-01-01], 0} -> duplicate_rows(10_000)
            _ -> []
          end
        end

      %{
        id: request.id,
        status: 200,
        body: %{"rows" => rows},
        raw_body: nil,
        metadata: request.metadata
      }
    end

    defp parse_id(id) do
      [date_iso, start_str] = String.split(id, ":")
      {Date.from_iso8601!(date_iso), String.to_integer(start_str)}
    end

    defp duplicate_rows(count) do
      row = %{"keys" => ["https://example.com/page", "query"], "clicks" => 1}
      List.duplicate(row, count)
    end
  end
end
