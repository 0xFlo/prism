defmodule GscAnalytics.DataSources.GSC.Core.Persistence do
  @moduledoc """
  All data persistence operations for GSC sync.

  This module provides a clean, organized interface for data storage operations,
  grouping related functionality into clear sections for better maintainability.

  ## Sections

  - **SyncDay Management** - Track sync status per day
  - **URL Performance** - Store and aggregate URL metrics
  - **Query Data** - Store search query associations
  - **Performance Aggregation** - Calculate aggregated metrics
  """

  import Ecto.Query
  require Logger

  alias GscAnalytics.Repo
  alias GscAnalytics.DateTime, as: AppDateTime
  alias GscAnalytics.Schemas.SyncDay
  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Support.QueryAccumulator

  # ============================================================================
  # SyncDay Management
  # ============================================================================

  @doc """
  Check if a specific day has already been synced.
  Returns true if a completed sync exists for the given date.
  """
  def day_already_synced?(account_id, site_url, date) do
    Repo.exists?(
      from sd in SyncDay,
        where:
          sd.account_id == ^account_id and
            sd.site_url == ^site_url and
            sd.date == ^date and
            sd.status == :complete
    )
  end

  @doc """
  Mark a sync day as running.
  """
  def mark_day_running(account_id, site_url, date) do
    upsert_sync_day(account_id, site_url, date, :running)
  end

  @doc """
  Mark a sync day as complete.
  """
  def mark_day_complete(account_id, site_url, date, opts \\ []) do
    upsert_sync_day(account_id, site_url, date, :complete, opts)
  end

  @doc """
  Mark a sync day as failed.
  """
  def mark_day_failed(account_id, site_url, date, error) do
    upsert_sync_day(account_id, site_url, date, :failed, error: error)
  end

  defp upsert_sync_day(account_id, site_url, date, status, opts \\ []) do
    timestamp = AppDateTime.utc_now()

    # Fields to update on conflict
    update_fields =
      [status: status, last_synced_at: timestamp]
      |> maybe_add(:url_count, opts[:url_count])
      |> maybe_add(:query_count, opts[:query_count])
      |> maybe_add(:error, opts[:error])

    # Build attributes
    attrs =
      %{
        account_id: account_id,
        site_url: site_url,
        date: date,
        status: status,
        last_synced_at: timestamp
      }
      |> maybe_put(:url_count, opts[:url_count])
      |> maybe_put(:query_count, opts[:query_count])
      |> maybe_put(:error, opts[:error])

    changeset = SyncDay.changeset(%SyncDay{}, attrs)

    case Repo.insert(
           changeset,
           on_conflict: [set: update_fields],
           conflict_target: [:account_id, :site_url, :date]
         ) do
      {:ok, sync_day} ->
        {:ok, sync_day}

      {:error, changeset} ->
        Logger.error("Failed to upsert SyncDay: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # ============================================================================
  # URL Performance Storage
  # ============================================================================

  @doc """
  Process and store GSC response data for URLs.
  Returns the count of URLs processed.
  """
  # Function header with default
  def process_url_response(account_id, site_url, date, data, opts \\ [])

  def process_url_response(account_id, site_url, date, %{"rows" => rows}, opts)
      when is_list(rows) do
    defer_refresh? = Keyword.get(opts, :defer_refresh, false)
    url_count = length(rows)

    # Prepare all time series records for bulk insert
    now = AppDateTime.utc_now()

    time_series_records =
      rows
      |> Enum.map(fn row ->
        url = get_in(row, ["keys", Access.at(0)])

        %{
          account_id: account_id,
          url: safe_truncate(url, 2048),
          property_url: safe_truncate(site_url, 255),
          date: date,
          clicks: row["clicks"] || 0,
          impressions: row["impressions"] || 0,
          ctr: ensure_float(row["ctr"] || 0.0),
          position: ensure_float(row["position"] || 0.0),
          data_available: true,
          period_type: :daily,
          inserted_at: now
        }
      end)

    # Bulk insert time series records in chunks to respect PostgreSQL parameter limits
    # With 10 fields per record, chunking at 500 keeps us well under the 65,535 parameter limit
    batch_size = Config.time_series_batch_size()

    total_inserted =
      time_series_records
      |> Enum.chunk_every(batch_size)
      |> Enum.reduce(0, fn chunk, acc ->
        {inserted, _} =
          Repo.insert_all(GscAnalytics.Schemas.TimeSeries, chunk,
            on_conflict: {:replace_all_except, [:inserted_at]},
            conflict_target: [:account_id, :property_url, :url, :date]
          )

        acc + inserted
      end)

    Logger.info("Stored #{total_inserted} URLs for #{site_url} on #{date}")

    # Extract URLs for refresh and HTTP checks
    urls_to_refresh = Enum.map(rows, fn row -> get_in(row, ["keys", Access.at(0)]) end)

    # Only refresh immediately if not deferring
    unless defer_refresh? do
      refresh_lifetime_stats_incrementally(account_id, site_url, urls_to_refresh)
    end

    # Enqueue automatic HTTP status checks for new URLs
    enqueue_http_status_checks(account_id, site_url, urls_to_refresh)

    # Return both count and URLs when deferring for later batch refresh
    if defer_refresh? do
      {url_count, urls_to_refresh}
    else
      url_count
    end
  end

  def process_url_response(_account_id, _site_url, date, _data, _opts) do
    Logger.warning("Unexpected GSC response format for #{date}")
    0
  end

  # ============================================================================
  # Query Data Storage
  # ============================================================================

  @doc """
  Process and store query data for URLs.
  Returns the count of query-URL pairs processed.
  """
  def process_query_response(account_id, site_url, date, %QueryAccumulator{} = accumulator) do
    now = AppDateTime.utc_now()
    batch_size = Config.query_batch_size()

    accumulator
    |> QueryAccumulator.entries()
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn chunk ->
      rows =
        Enum.map(chunk, fn {url, queries} ->
          %{
            account_id: account_id,
            property_url: site_url,
            url: url,
            date: date,
            top_queries: queries,
            inserted_at: now
          }
        end)

      Repo.insert_all(
        GscAnalytics.Schemas.TimeSeries,
        rows,
        on_conflict: {:replace, [:top_queries]},
        conflict_target: [:account_id, :property_url, :url, :date]
      )
    end)

    QueryAccumulator.row_count(accumulator)
  end

  def process_query_response(account_id, site_url, date, query_rows) do
    # Group queries by URL and take top 20 per URL
    queries_by_url =
      query_rows
      |> Enum.group_by(
        fn row -> get_in(row, ["keys", Access.at(0)]) end,
        fn row ->
          query = get_in(row, ["keys", Access.at(1)])

          %{
            query: query,
            clicks: row["clicks"] || 0,
            impressions: row["impressions"] || 0,
            ctr: ensure_float(row["ctr"] || 0.0),
            position: ensure_float(row["position"] || 0.0)
          }
        end
      )
      |> Enum.map(fn {url, queries} ->
        # Sort by clicks descending, take top 20
        sorted_queries =
          queries
          |> Enum.sort_by(& &1.clicks, :desc)
          |> Enum.take(20)

        {url, sorted_queries}
      end)

    # Prepare records for bulk upsert
    now = AppDateTime.utc_now()

    time_series_updates =
      Enum.map(queries_by_url, fn {url, queries} ->
        %{
          account_id: account_id,
          property_url: site_url,
          url: url,
          date: date,
          top_queries: queries,
          inserted_at: now
        }
      end)

    # Bulk update using insert_all with on_conflict
    # Process in chunks to respect PostgreSQL parameter limits
    batch_size = Config.query_batch_size()

    time_series_updates
    |> Enum.chunk_every(batch_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(
        GscAnalytics.Schemas.TimeSeries,
        chunk,
        on_conflict: {:replace, [:top_queries]},
        conflict_target: [:account_id, :property_url, :url, :date]
      )
    end)

    length(query_rows)
  end

  # ============================================================================
  # Materialized View Refresh
  # ============================================================================

  @doc """
  Incrementally refresh the url_lifetime_stats materialized view for specific URLs.
  This is much more efficient than refreshing the entire view.

  URLs are processed in batches to:
  - Avoid PostgreSQL array size limits (practical limit ~5,000-10,000 elements)
  - Reduce transaction lock time (smaller transactions = better concurrency)
  - Prevent memory pressure on large datasets
  """
  def refresh_lifetime_stats_incrementally(_account_id, _property_url, urls) when urls == [] do
    :ok
  end

  def refresh_lifetime_stats_incrementally(account_id, property_url, urls) when is_list(urls) do
    batch_size = Config.lifetime_stats_batch_size()
    total_urls = length(urls)

    # Process URLs in batches to avoid PostgreSQL parameter/array limits
    urls
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {url_batch, batch_num} ->
      refresh_url_batch(account_id, property_url, url_batch, batch_num, total_urls)
    end)

    :ok
  rescue
    e ->
      Logger.error("Failed to refresh lifetime stats for URLs: #{inspect(e)}")
      {:error, e}
  end

  defp refresh_url_batch(account_id, property_url, urls, _batch_num, _total_batches) do
    # Use UPSERT (INSERT ... ON CONFLICT DO UPDATE) instead of DELETE+INSERT
    # This is significantly faster and avoids table fragmentation
    Repo.query!(
      """
      INSERT INTO url_lifetime_stats (
        account_id, property_url, url,
        lifetime_clicks, lifetime_impressions,
        avg_position, avg_ctr,
        first_seen_date, last_seen_date,
        days_with_data, refreshed_at
      )
      SELECT
        account_id, property_url, url,
        SUM(clicks) as lifetime_clicks,
        SUM(impressions) as lifetime_impressions,
        CASE
          WHEN SUM(impressions) > 0
          THEN SUM(position * impressions) / SUM(impressions)
          ELSE 0.0
        END as avg_position,
        CASE
          WHEN SUM(impressions) > 0
          THEN SUM(clicks)::DOUBLE PRECISION / SUM(impressions)
          ELSE 0.0
        END as avg_ctr,
        MIN(date) as first_seen_date,
        MAX(date) as last_seen_date,
        COUNT(DISTINCT date) as days_with_data,
        NOW() as refreshed_at
      FROM gsc_time_series
      WHERE account_id = $1
        AND property_url = $2
        AND url = ANY($3::text[])
        AND data_available = true
      GROUP BY account_id, property_url, url
      ON CONFLICT (account_id, property_url, url)
      DO UPDATE SET
        lifetime_clicks = EXCLUDED.lifetime_clicks,
        lifetime_impressions = EXCLUDED.lifetime_impressions,
        avg_position = EXCLUDED.avg_position,
        avg_ctr = EXCLUDED.avg_ctr,
        first_seen_date = EXCLUDED.first_seen_date,
        last_seen_date = EXCLUDED.last_seen_date,
        days_with_data = EXCLUDED.days_with_data,
        refreshed_at = EXCLUDED.refreshed_at
      """,
      [account_id, property_url, urls]
    )
  end

  # ============================================================================
  # Performance Aggregation (DEPRECATED - Will be removed)
  # ============================================================================

  @doc """
  Aggregate performance metrics for specific URLs within a property that were just synced.
  This is optimized to only process the URLs that changed, not all URLs.

  DEPRECATED: This function is being replaced by refresh_lifetime_stats_incrementally/2
  """
  def aggregate_performance_for_urls(account_id, property_url, urls, date) when is_list(urls) do
    if urls == [] do
      :ok
    else
      # Process in chunks for memory efficiency
      batch_size = Config.db_batch_size()

      urls
      |> Enum.chunk_every(batch_size)
      |> Enum.each(fn url_chunk ->
        aggregate_url_chunk(account_id, property_url, url_chunk, date)
      end)

      :ok
    end
  end

  @doc """
  Refresh performance cache for a single URL.
  Recalculates aggregated metrics for the last N days.
  """
  def refresh_performance_cache(account_id, property_url, url, days \\ nil) do
    days = days || Config.performance_aggregation_days()
    start_date = Date.add(Date.utc_today(), -days)

    # Get aggregated totals
    totals =
      from(ts in GscAnalytics.Schemas.TimeSeries,
        where:
          ts.account_id == ^account_id and
            ts.property_url == ^property_url and
            ts.url == ^url and
            ts.date >= ^start_date,
        select: %{
          total_clicks: sum(ts.clicks),
          total_impressions: sum(ts.impressions),
          min_date: min(ts.date),
          max_date: max(ts.date)
        }
      )
      |> Repo.one()

    case totals do
      %{total_clicks: clicks, total_impressions: impressions, min_date: min_date}
      when not is_nil(clicks) and not is_nil(impressions) and not is_nil(min_date) ->
        # Calculate weighted average position
        avg_position =
          from(ts in GscAnalytics.Schemas.TimeSeries,
            where:
              ts.account_id == ^account_id and
                ts.property_url == ^property_url and
                ts.url == ^url and
                ts.date >= ^start_date,
            select:
              fragment(
                "SUM(? * ?) / NULLIF(SUM(?), 0)",
                ts.position,
                ts.impressions,
                ts.impressions
              )
          )
          |> Repo.one() || 0.0

        avg_ctr = if impressions > 0, do: clicks / impressions, else: 0.0

        attrs = %{
          account_id: account_id,
          property_url: property_url,
          url: url,
          clicks: clicks,
          impressions: impressions,
          ctr: avg_ctr,
          position: avg_position,
          date_range_start: totals.min_date,
          date_range_end: totals.max_date,
          data_available: true,
          fetched_at: AppDateTime.utc_now()
        }

        # Upsert Performance record
        case Repo.get_by(GscAnalytics.Schemas.Performance,
               account_id: account_id,
               property_url: property_url,
               url: url
             ) do
          nil ->
            %GscAnalytics.Schemas.Performance{}
            |> GscAnalytics.Schemas.Performance.changeset(attrs)
            |> Repo.insert()

          existing ->
            existing
            |> GscAnalytics.Schemas.Performance.changeset(attrs)
            |> Repo.update()
        end

      _ ->
        {:ok, nil}
    end
  rescue
    e ->
      Logger.error("Failed to refresh performance for #{url}: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Get time-series data for a URL within a date range.
  """
  def get_time_series(account_id, property_url, url, start_date, end_date) do
    from(ts in GscAnalytics.Schemas.TimeSeries,
      where:
        ts.account_id == ^account_id and
          ts.property_url == ^property_url and
          ts.url == ^url and
          ts.date >= ^start_date and
          ts.date <= ^end_date,
      order_by: [asc: ts.date]
    )
    |> Repo.all()
  end

  @doc """
  Get aggregated performance for a URL.
  """
  def get_performance(account_id, property_url, url) do
    Repo.get_by(GscAnalytics.Schemas.Performance,
      account_id: account_id,
      property_url: property_url,
      url: url
    )
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp aggregate_url_chunk(account_id, property_url, url_chunk, date) do
    days_ago = Config.performance_aggregation_days()
    start_date = Date.add(date, -days_ago)

    # Get aggregated metrics for this chunk of URLs in a single query
    metrics_by_url =
      from(ts in GscAnalytics.Schemas.TimeSeries,
        where:
          ts.account_id == ^account_id and
            ts.property_url == ^property_url and
            ts.url in ^url_chunk and
            ts.date >= ^start_date and
            ts.date <= ^date,
        group_by: ts.url,
        select: {
          ts.url,
          %{
            clicks: sum(ts.clicks),
            impressions: sum(ts.impressions),
            position: avg(ts.position),
            ctr: avg(ts.ctr),
            min_date: min(ts.date),
            max_date: max(ts.date)
          }
        }
      )
      |> Repo.all()
      |> Map.new()

    # Build performance records for bulk upsert
    now = AppDateTime.utc_now()

    performance_records =
      url_chunk
      |> Enum.filter(fn url -> Map.has_key?(metrics_by_url, url) end)
      |> Enum.map(fn url ->
        metrics = Map.get(metrics_by_url, url)

        %{
          id: Ecto.UUID.generate(),
          account_id: account_id,
          property_url: property_url,
          url: url,
          clicks: metrics.clicks || 0,
          impressions: metrics.impressions || 0,
          position: ensure_float(metrics.position || 0.0),
          ctr: ensure_float(metrics.ctr || 0.0),
          date_range_start: metrics.min_date,
          date_range_end: metrics.max_date,
          data_available: true,
          fetched_at: now,
          cache_expires_at: DateTime.add(now, 86400, :second),
          inserted_at: now,
          updated_at: now
        }
      end)

    # Bulk upsert performance records
    if performance_records != [] do
      Repo.insert_all(GscAnalytics.Schemas.Performance, performance_records,
        on_conflict:
          {:replace,
           [
             :clicks,
             :impressions,
             :position,
             :ctr,
             :date_range_start,
             :date_range_end,
             :fetched_at,
             :cache_expires_at,
             :updated_at
           ]},
        conflict_target: [:account_id, :property_url, :url]
      )
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: list ++ [{key, value}]

  # Ensure a value is a float (handles integers from API)
  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value / 1.0

  defp ensure_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  defp ensure_float(_), do: 0.0

  # Safely truncate strings to avoid database length constraint errors
  # Logs a warning if truncation occurs
  defp safe_truncate(nil, _max_length), do: nil

  defp safe_truncate(string, max_length) when is_binary(string) do
    if String.length(string) > max_length do
      truncated = String.slice(string, 0, max_length)

      Logger.warning(
        "Truncated overly long string from #{String.length(string)} to #{max_length} characters: #{String.slice(string, 0, 100)}..."
      )

      truncated
    else
      string
    end
  end

  defp safe_truncate(value, _max_length), do: value

  # ============================================================================
  # Automatic HTTP Status Checking
  # ============================================================================

  # Enqueue HTTP status checks for newly discovered URLs.
  # This function is called automatically after URL sync to validate
  # HTTP status codes in the background. Only URLs that haven't been
  # checked recently are enqueued.
  #
  # CRITICAL: This filters URLs to only enqueue those that actually need
  # checking, preventing duplicate work and race conditions.
  #
  # BACKPRESSURE: For large batches (>1000 URLs), implements intelligent
  # throttling by spreading job scheduling over time to prevent queue
  # overload and resource exhaustion.
  defp enqueue_http_status_checks(account_id, property_url, urls) do
    # Only enqueue if the worker module is available (may not be in test env)
    if Code.ensure_loaded?(GscAnalytics.Workers.HttpStatusCheckWorker) do
      # Filter to only URLs that need checking (unchecked or stale)
      # This prevents duplicate enqueueing on re-syncs
      urls_needing_check = filter_urls_needing_check(account_id, property_url, urls)

      if urls_needing_check != [] do
        # Apply backpressure for large batches
        enqueue_opts = apply_backpressure(length(urls_needing_check))

        # Use Task.Supervisor for proper error handling and monitoring
        case Task.Supervisor.start_child(
               GscAnalytics.TaskSupervisor,
               fn ->
                 GscAnalytics.Workers.HttpStatusCheckWorker.enqueue_new_urls(
                   [
                     account_id: account_id,
                     property_url: property_url,
                     urls: urls_needing_check
                   ] ++ enqueue_opts
                 )
               end,
               restart: :transient
             ) do
          {:ok, _pid} ->
            Logger.debug(
              "Enqueued HTTP checks for #{length(urls_needing_check)}/#{length(urls)} URLs #{format_enqueue_opts(enqueue_opts)}"
            )

          {:error, reason} ->
            Logger.error("Failed to start HTTP check enqueue task: #{inspect(reason)}")
        end
      else
        Logger.debug("All #{length(urls)} URLs recently checked, skipping enqueue")
      end
    end

    :ok
  rescue
    e ->
      Logger.error("Failed to enqueue HTTP status checks: #{inspect(e)}")
      :ok
  end

  # Apply backpressure based on batch size to prevent overwhelming
  # the Oban queue and consuming too many resources at once.
  #
  # Strategy:
  # - Small batches (< 500): Immediate, high priority
  # - Medium batches (500-2000): Delayed start, spread over 5 minutes
  # - Large batches (2000-5000): Lower priority, spread over 15 minutes
  # - Huge batches (> 5000): Background priority, spread over 30 minutes
  defp apply_backpressure(url_count) do
    cond do
      url_count < 500 ->
        # Small batch: immediate, high priority
        [priority: 1, schedule_in: 60]

      url_count < 2000 ->
        # Medium batch: spread over 5 minutes
        delay = :rand.uniform(300)
        [priority: 2, schedule_in: delay]

      url_count < 5000 ->
        # Large batch: spread over 15 minutes, lower priority
        delay = :rand.uniform(900)
        [priority: 2, schedule_in: delay]

      true ->
        # Huge batch: spread over 30 minutes, background priority
        delay = :rand.uniform(1800)
        [priority: 3, schedule_in: delay]
    end
  end

  defp format_enqueue_opts(opts) do
    priority = Keyword.get(opts, :priority)
    schedule_in = Keyword.get(opts, :schedule_in)
    "(priority: #{priority}, delay: #{schedule_in}s)"
  end

  # Filter URLs to only those that need HTTP status checking.
  # Returns URLs that are either:
  # - Never checked (http_status IS NULL)
  # - Stale (checked > 7 days ago)
  # This prevents duplicate work when re-syncing the same date ranges.
  defp filter_urls_needing_check(account_id, property_url, urls) do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    # Query for URLs that need checking
    url_status_map =
      from(p in GscAnalytics.Schemas.Performance,
        where:
          p.account_id == ^account_id and
            p.property_url == ^property_url and
            p.url in ^urls and
            (is_nil(p.http_status) or p.http_checked_at < ^seven_days_ago),
        select: p.url
      )
      |> Repo.all()
      |> MapSet.new()

    # Return only URLs that are in the "needs checking" set
    Enum.filter(urls, fn url -> MapSet.member?(url_status_map, url) end)
  end
end
