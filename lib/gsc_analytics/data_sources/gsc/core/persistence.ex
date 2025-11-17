defmodule GscAnalytics.DataSources.GSC.Core.Persistence do
  @moduledoc """
  Facade for GSC persistence operations.

  The persistence layer is split across specialized modules:

    * `Persistence.SyncDays` – track per-day sync state
    * `Persistence.Urls` – store URL metrics and lifetime aggregates
    * `Persistence.Queries` – store query associations per URL

  This module keeps the public API stable while delegating to the focused
  implementations above.
  """

  alias GscAnalytics.DataSources.GSC.Core.Persistence.{Queries, SyncDays, Urls}

  # Sync day management -------------------------------------------------------
  defdelegate day_already_synced?(account_id, site_url, date), to: SyncDays
  defdelegate mark_day_running(account_id, site_url, date), to: SyncDays
  defdelegate mark_day_complete(account_id, site_url, date, opts \\ []), to: SyncDays
  defdelegate mark_day_failed(account_id, site_url, date, error), to: SyncDays

  # URL storage / aggregates --------------------------------------------------
  defdelegate process_url_response(account_id, site_url, date, data, opts \\ []), to: Urls
  defdelegate refresh_lifetime_stats_incrementally(account_id, property_url, urls), to: Urls
  defdelegate aggregate_performance_for_urls(account_id, property_url, urls, date), to: Urls
  defdelegate refresh_performance_cache(account_id, property_url, url, days \\ nil), to: Urls
  defdelegate get_time_series(account_id, property_url, url, start_date, end_date), to: Urls
  defdelegate get_performance(account_id, property_url, url), to: Urls

  # Query storage -------------------------------------------------------------
  def process_query_response(account_id, site_url, date, payload) do
    Queries.process_query_response(account_id, site_url, date, payload)
  end
end
