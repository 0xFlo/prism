defmodule GscAnalytics.Crawler.Persistence do
  @moduledoc """
  Persistence layer for saving HTTP status check results.

  This module handles saving check results to the url_lifetime_stats table
  and mirrors those HTTP fields back to the legacy gsc_performance table so
  existing dashboards stay in sync. Results are persisted in bulk batches to
  avoid hammering the database with one UPDATE per URL.

  ## Important: Table Architecture
  - Primary data table: `url_lifetime_stats` (materialized view with HTTP fields)
  - Legacy table: `gsc_performance` (kept empty, may be deprecated)

  The crawler updates HTTP status fields directly in url_lifetime_stats,
  which contains aggregated GSC performance data.

  ## Features
  - Single URL updates
  - Batch updates for concurrent operations
  - Partial failure handling
  - Only updates HTTP status fields (doesn't touch GSC metrics)
  """

  require Logger

  alias GscAnalytics.Repo

  @batch_size 100
  @bulk_update_sql """
  WITH data AS (
    SELECT
      rows.url,
      rows.http_status,
      rows.redirect_url,
      rows.http_checked_at,
      (rows.http_redirect_chain)::jsonb AS http_redirect_chain
    FROM unnest(
      $1::text[],
      $2::integer[],
      $3::text[],
      $4::timestamptz[],
      $5::text[]
    ) AS rows(url, http_status, redirect_url, http_checked_at, http_redirect_chain)
  ),
  updated_lifetime AS (
    UPDATE url_lifetime_stats AS u
    SET
      http_status = data.http_status,
      redirect_url = data.redirect_url,
      http_checked_at = data.http_checked_at,
      http_redirect_chain = data.http_redirect_chain
    FROM data
    WHERE u.url = data.url
    RETURNING
      u.account_id,
      u.property_url,
      u.url,
      data.http_status,
      data.redirect_url,
      data.http_checked_at,
      data.http_redirect_chain
  ),
  updated_performance AS (
    UPDATE gsc_performance AS p
    SET
      http_status = updated_lifetime.http_status,
      redirect_url = updated_lifetime.redirect_url,
      http_checked_at = updated_lifetime.http_checked_at,
      http_redirect_chain = updated_lifetime.http_redirect_chain,
      updated_at = NOW()
    FROM updated_lifetime
    WHERE p.account_id = updated_lifetime.account_id
      AND p.property_url = updated_lifetime.property_url
      AND p.url = updated_lifetime.url
    RETURNING 1
  )
  SELECT
    COALESCE((SELECT count(*) FROM updated_lifetime), 0) AS lifetime_count,
    COALESCE((SELECT count(*) FROM updated_performance), 0) AS performance_count
  """

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Save a single check result.

  ## Parameters
    - `url` - The URL that was checked
    - `result` - The check result map from HttpStatus

  ## Returns
    - `{:ok, updated_count}` - Successfully updated
    - `{:error, reason}` - Update failed
  """
  @spec save_result(String.t(), map()) :: {:ok, integer()} | {:error, term()}
  def save_result(url, result) do
    save_batch([{url, result}])
  end

  @doc """
  Save multiple check results in a batch.

  Updates are performed in chunks to avoid parameter limits.

  ## Parameters
    - `results` - List of `{url, result}` tuples

  ## Returns
    - `{:ok, total_updated}` - Total number of records updated
    - `{:error, reason}` - Batch update failed
  """
  @spec save_batch(list({String.t(), map()})) :: {:ok, integer()} | {:error, term()}
  def save_batch(results) when is_list(results) do
    total_updated =
      results
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(0, fn chunk, acc ->
        {:ok, count} = update_chunk(chunk)
        acc + count
      end)

    {:ok, total_updated}
  end

  # ============================================================================
  # Private - Batch Updates
  # ============================================================================

  defp update_chunk([]), do: {:ok, 0}

  defp update_chunk(results) do
    urls = Enum.map(results, fn {url, _} -> url end)
    statuses = Enum.map(results, fn {_, result} -> result.status end)
    redirect_urls = Enum.map(results, fn {_, result} -> result.redirect_url end)
    checked_at = Enum.map(results, fn {_, result} -> result.checked_at end)

    redirect_chains =
      Enum.map(results, fn {_, result} ->
        case result.redirect_chain do
          nil -> nil
          chain when chain == %{} -> "{}"
          chain -> JSON.encode!(chain)
        end
      end)

    params = [urls, statuses, redirect_urls, checked_at, redirect_chains]

    case Repo.query(@bulk_update_sql, params) do
      {:ok, %{rows: [[lifetime_count, performance_count]]}} ->
        total = length(results)

        if lifetime_count < total do
          Logger.debug(
            "HTTP status batch processed #{total} results but only #{lifetime_count} URLs existed in url_lifetime_stats"
          )
        end

        cond do
          lifetime_count == 0 ->
            Logger.debug(
              "HTTP status batch skipped because none of the URLs exist in url_lifetime_stats"
            )

          performance_count == 0 ->
            Logger.debug(
              "HTTP status batch updated #{lifetime_count} rows in url_lifetime_stats but legacy gsc_performance had no matching rows; mirroring skipped"
            )

          lifetime_count > performance_count ->
            Logger.warning(
              "HTTP status batch updated #{lifetime_count} rows in url_lifetime_stats but only #{performance_count} rows in gsc_performance; dashboard data may be missing"
            )

          true ->
            :ok
        end

        {:ok, total}

      {:error, error} ->
        Logger.error("Failed to persist HTTP status batch: #{inspect(error)}")
        {:error, error}
    end
  end
end
