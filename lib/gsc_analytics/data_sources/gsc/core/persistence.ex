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
  def process_url_response(account_id, site_url, date, %{"rows" => rows})
      when is_list(rows) do
    url_count = length(rows)

    Logger.debug("Processing #{url_count} URLs for #{site_url} on #{date}")

    # Prepare all time series records for bulk insert
    now = AppDateTime.utc_now()

    time_series_records =
      rows
      |> Enum.map(fn row ->
        url = get_in(row, ["keys", Access.at(0)])

        %{
          account_id: account_id,
          url: url,
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
            conflict_target: [:account_id, :url, :date]
          )

        Logger.debug("Inserted #{inserted} time_series records (chunk of #{length(chunk)})")
        acc + inserted
      end)

    Logger.debug("Total inserted: #{total_inserted} time_series records across #{ceil(url_count / batch_size)} chunks")

    # Refresh materialized view for these URLs only
    urls_to_refresh = Enum.map(rows, fn row -> get_in(row, ["keys", Access.at(0)]) end)
    refresh_lifetime_stats_incrementally(account_id, urls_to_refresh)

    url_count
  end

  def process_url_response(_account_id, _site_url, date, _data) do
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
  def process_query_response(account_id, _site_url, date, query_rows) do
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
        conflict_target: [:account_id, :url, :date]
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
  def refresh_lifetime_stats_incrementally(_account_id, urls) when urls == [] do
    :ok
  end

  def refresh_lifetime_stats_incrementally(account_id, urls) when is_list(urls) do
    batch_size = Config.lifetime_stats_batch_size()
    total_urls = length(urls)
    total_batches = ceil(total_urls / batch_size)

    Logger.debug(
      "Refreshing lifetime stats for #{total_urls} URLs across #{total_batches} batches (batch_size=#{batch_size})"
    )

    # Process URLs in batches to avoid PostgreSQL parameter/array limits
    urls
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {url_batch, batch_num} ->
      refresh_url_batch(account_id, url_batch, batch_num, total_batches)
    end)

    :ok
  rescue
    e ->
      Logger.error("Failed to refresh lifetime stats for URLs: #{inspect(e)}")
      {:error, e}
  end

  defp refresh_url_batch(account_id, urls, batch_num, total_batches) do
    batch_start = System.monotonic_time(:millisecond)

    Repo.transaction(fn ->
      # Step 1: Delete existing stats for this batch of URLs
      delete_result =
        Repo.query!(
          """
          DELETE FROM url_lifetime_stats
          WHERE account_id = $1 AND url = ANY($2::text[])
          """,
          [account_id, urls]
        )

      # Step 2: Recalculate and insert fresh stats for this batch
      insert_result =
        Repo.query!(
          """
          INSERT INTO url_lifetime_stats (
            account_id, url,
            lifetime_clicks, lifetime_impressions,
            avg_position, avg_ctr,
            first_seen_date, last_seen_date,
            days_with_data, refreshed_at
          )
          SELECT
            account_id, url,
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
            AND url = ANY($2::text[])
            AND data_available = true
          GROUP BY account_id, url
          """,
          [account_id, urls]
        )

      batch_duration = System.monotonic_time(:millisecond) - batch_start

      Logger.debug(
        "Batch #{batch_num}/#{total_batches}: Deleted #{delete_result.num_rows}, " <>
          "Inserted #{insert_result.num_rows} lifetime stats in #{batch_duration}ms"
      )
    end)
  end

  # ============================================================================
  # Performance Aggregation (DEPRECATED - Will be removed)
  # ============================================================================

  @doc """
  Aggregate performance metrics for specific URLs that were just synced.
  This is optimized to only process the URLs that changed, not all URLs.

  DEPRECATED: This function is being replaced by refresh_lifetime_stats_incrementally/2
  """
  def aggregate_performance_for_urls(account_id, urls, date) when is_list(urls) do
    if urls == [] do
      :ok
    else
      # Process in chunks for memory efficiency
      batch_size = Config.db_batch_size()

      urls
      |> Enum.chunk_every(batch_size)
      |> Enum.each(fn url_chunk ->
        aggregate_url_chunk(account_id, url_chunk, date)
      end)

      :ok
    end
  end

  @doc """
  Refresh performance cache for a single URL.
  Recalculates aggregated metrics for the last N days.
  """
  def refresh_performance_cache(account_id, url, days \\ nil) do
    days = days || Config.performance_aggregation_days()
    start_date = Date.add(Date.utc_today(), -days)

    # Get aggregated totals
    totals =
      from(ts in GscAnalytics.Schemas.TimeSeries,
        where:
          ts.account_id == ^account_id and
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
        case Repo.get_by(GscAnalytics.Schemas.Performance, account_id: account_id, url: url) do
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
  def get_time_series(account_id, url, start_date, end_date) do
    from(ts in GscAnalytics.Schemas.TimeSeries,
      where:
        ts.account_id == ^account_id and
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
  def get_performance(account_id, url) do
    Repo.get_by(GscAnalytics.Schemas.Performance, account_id: account_id, url: url)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp aggregate_url_chunk(account_id, url_chunk, date) do
    days_ago = Config.performance_aggregation_days()
    start_date = Date.add(date, -days_ago)

    # Get aggregated metrics for this chunk of URLs in a single query
    metrics_by_url =
      from(ts in GscAnalytics.Schemas.TimeSeries,
        where:
          ts.account_id == ^account_id and
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
        conflict_target: [:account_id, :url]
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
end
