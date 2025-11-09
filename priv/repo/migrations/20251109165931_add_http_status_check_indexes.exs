defmodule GscAnalytics.Repo.Migrations.AddHttpStatusCheckIndexes do
  use Ecto.Migration

  @moduledoc """
  Adds performance indexes for automatic HTTP status checking feature.

  These indexes optimize the query in `filter_urls_needing_check/3` which
  identifies stale or unchecked URLs during GSC sync operations.
  """

  def up do
    # Composite index for HTTP status check queries
    # Optimizes: WHERE account_id = X AND property_url = Y AND url IN (...) AND (http_status IS NULL OR http_checked_at < ...)
    # This query is executed on EVERY GSC sync to filter URLs needing checks
    create_if_not_exists index(
                           :gsc_performance,
                           [:account_id, :property_url, :http_checked_at, :http_status],
                           name: :idx_performance_http_check_filter,
                           comment: "Optimizes URL filtering for automatic HTTP status checking"
                         )

    # Index for finding stale URLs by status and check date
    # Optimizes: ORDER BY CASE WHEN http_status IS NULL THEN 0 WHEN http_status >= 400 THEN 1 ELSE 2 END
    # Used in HttpStatusCheckWorker.enqueue_stale_urls/1 for prioritization
    create_if_not_exists index(
                           :gsc_performance,
                           [:account_id, :http_status, :http_checked_at],
                           name: :idx_performance_stale_urls,
                           comment: "Optimizes stale URL detection and prioritization"
                         )

    # Partial index for never-checked URLs (highest priority)
    # Optimizes: WHERE http_status IS NULL
    # Dramatically speeds up queries for URLs that have never been checked
    create_if_not_exists index(
                           :gsc_performance,
                           [:account_id, :property_url],
                           where: "http_status IS NULL",
                           name: :idx_performance_unchecked_urls,
                           comment: "Fast lookup for never-checked URLs"
                         )

    # Partial index for recently broken links (re-check priority)
    # Optimizes: WHERE http_status >= 400 AND http_checked_at < (NOW() - INTERVAL '3 days')
    # Helps identify broken links that need re-checking
    create_if_not_exists index(
                           :gsc_performance,
                           [:account_id, :http_checked_at],
                           where: "http_status >= 400",
                           name: :idx_performance_broken_links,
                           comment: "Fast lookup for broken links needing re-check"
                         )
  end

  def down do
    drop_if_exists index(
                     :gsc_performance,
                     [:account_id, :property_url, :http_checked_at, :http_status],
                     name: :idx_performance_http_check_filter
                   )

    drop_if_exists index(:gsc_performance, [:account_id, :http_status, :http_checked_at],
                     name: :idx_performance_stale_urls
                   )

    drop_if_exists index(:gsc_performance, [:account_id, :property_url],
                     where: "http_status IS NULL",
                     name: :idx_performance_unchecked_urls
                   )

    drop_if_exists index(:gsc_performance, [:account_id, :http_checked_at],
                     where: "http_status >= 400",
                     name: :idx_performance_broken_links
                   )
  end
end
