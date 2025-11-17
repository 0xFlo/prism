defmodule GscAnalytics.DataSources.GSC.Core.Persistence.Urls do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Core.Persistence.Helpers
  alias GscAnalytics.DateTime, as: AppDateTime
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.PropertyDailyMetric

  @doc """
  Process and store GSC response data for URLs.
  """
  def process_url_response(account_id, site_url, date, data, opts \\ [])

  def process_url_response(account_id, site_url, date, %{"rows" => rows}, opts)
      when is_list(rows) do
    defer_refresh? = Keyword.get(opts, :defer_refresh, false)
    url_count = length(rows)
    now = AppDateTime.utc_now()

    time_series_records =
      rows
      |> Enum.map(fn row ->
        url = get_in(row, ["keys", Access.at(0)])

        %{
          account_id: account_id,
          url: Helpers.safe_truncate(url, 2048),
          property_url: Helpers.safe_truncate(site_url, 255),
          date: date,
          clicks: row["clicks"] || 0,
          impressions: row["impressions"] || 0,
          ctr: Helpers.ensure_float(row["ctr"] || 0.0),
          position: Helpers.ensure_float(row["position"] || 0.0),
          data_available: true,
          period_type: :daily,
          inserted_at: now
        }
      end)

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

    upsert_property_daily_metrics(account_id, site_url, date, rows)

    urls_to_refresh = Enum.map(rows, fn row -> get_in(row, ["keys", Access.at(0)]) end)

    unless defer_refresh? do
      refresh_lifetime_stats_incrementally(account_id, site_url, urls_to_refresh)
    end

    enqueue_http_status_checks(account_id, site_url, urls_to_refresh)

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

  @doc """
  Incrementally refresh the url_lifetime_stats materialized view for specific URLs.
  """
  def refresh_lifetime_stats_incrementally(_account_id, _property_url, urls) when urls == [] do
    :ok
  end

  def refresh_lifetime_stats_incrementally(account_id, property_url, urls) when is_list(urls) do
    batch_size = Config.lifetime_stats_batch_size()
    timeout = Config.lifetime_stats_timeout()
    total_urls = length(urls)

    urls
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {url_batch, batch_num} ->
      refresh_url_batch(account_id, property_url, url_batch, batch_num, total_urls, timeout)
    end)

    :ok
  rescue
    e ->
      Logger.error("Failed to refresh lifetime stats for URLs: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Aggregate performance metrics for specific URLs within a property that were just synced.
  """
  def aggregate_performance_for_urls(account_id, property_url, urls, date) when is_list(urls) do
    if urls == [] do
      :ok
    else
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
  """
  def refresh_performance_cache(account_id, property_url, url, days \\ nil) do
    days = days || Config.performance_aggregation_days()
    start_date = Date.add(Date.utc_today(), -days)

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

  defp refresh_url_batch(account_id, property_url, urls, _batch_num, _total_batches, timeout) do
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
      [account_id, property_url, urls],
      timeout: timeout,
      log: false
    )
  end

  defp aggregate_url_chunk(account_id, property_url, url_chunk, date) do
    days_ago = Config.performance_aggregation_days()
    start_date = Date.add(date, -days_ago)

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
          position: Helpers.ensure_float(metrics.position || 0.0),
          ctr: Helpers.ensure_float(metrics.ctr || 0.0),
          date_range_start: metrics.min_date,
          date_range_end: metrics.max_date,
          data_available: true,
          fetched_at: now,
          cache_expires_at: DateTime.add(now, 86_400, :second),
          inserted_at: now,
          updated_at: now
        }
      end)

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

  defp enqueue_http_status_checks(_account_id, _property_url, urls) when urls == [], do: :ok

  defp enqueue_http_status_checks(account_id, property_url, urls) do
    if Code.ensure_loaded?(GscAnalytics.Workers.HttpStatusCheckWorker) do
      urls_needing_check = filter_urls_needing_check(account_id, property_url, urls)

      if urls_needing_check != [] do
        enqueue_opts = apply_backpressure(length(urls_needing_check))

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

  defp apply_backpressure(url_count) do
    cond do
      url_count < 500 ->
        [priority: 1, schedule_in: 60]

      url_count < 2000 ->
        delay = :rand.uniform(300)
        [priority: 2, schedule_in: delay]

      url_count < 5000 ->
        delay = :rand.uniform(900)
        [priority: 2, schedule_in: delay]

      true ->
        delay = :rand.uniform(1800)
        [priority: 3, schedule_in: delay]
    end
  end

  defp format_enqueue_opts(opts) do
    priority = Keyword.get(opts, :priority)
    schedule_in = Keyword.get(opts, :schedule_in)
    "(priority: #{priority}, delay: #{schedule_in}s)"
  end

  defp filter_urls_needing_check(account_id, property_url, urls) do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

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

    Enum.filter(urls, fn url -> MapSet.member?(url_status_map, url) end)
  end

  defp upsert_property_daily_metrics(account_id, property_url, date, rows) do
    now = AppDateTime.utc_now()

    totals =
      Enum.reduce(
        rows,
        %{clicks: 0, impressions: 0, weighted_position: 0.0, urls: MapSet.new()},
        fn row, acc ->
          url = get_in(row, ["keys", Access.at(0)])
          clicks = row["clicks"] || 0
          impressions = row["impressions"] || 0
          position = Helpers.ensure_float(row["position"] || 0.0)

          %{
            clicks: acc.clicks + clicks,
            impressions: acc.impressions + impressions,
            weighted_position: acc.weighted_position + position * impressions,
            urls: MapSet.put(acc.urls, url)
          }
        end
      )

    impressions = totals.impressions
    clicks = totals.clicks
    urls_count = MapSet.size(totals.urls)

    avg_position =
      if impressions > 0 do
        totals.weighted_position / impressions
      else
        0.0
      end

    avg_ctr =
      if impressions > 0 do
        clicks / impressions
      else
        0.0
      end

    Repo.insert_all(
      PropertyDailyMetric,
      [
        %{
          account_id: account_id,
          property_url: property_url,
          date: date,
          clicks: clicks,
          impressions: impressions,
          position: avg_position,
          ctr: avg_ctr,
          urls_count: urls_count,
          data_available: urls_count > 0,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        {:replace,
         [:clicks, :impressions, :ctr, :position, :urls_count, :data_available, :updated_at]},
      conflict_target: [:account_id, :property_url, :date]
    )
  end
end
