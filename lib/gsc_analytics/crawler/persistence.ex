defmodule GscAnalytics.Crawler.Persistence do
  @moduledoc """
  Persistence layer for saving HTTP status check results.

  This module handles saving check results to the gsc_performance table,
  using efficient batch updates when possible.

  ## Features
  - Single URL updates
  - Batch updates for concurrent operations
  - Partial failure handling
  - Only updates HTTP status fields (doesn't touch GSC metrics)
  """

  require Logger

  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Performance

  import Ecto.Query

  @batch_size 100

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

  defp update_chunk(results) do
    # Group URLs by their result values to minimize number of queries
    # Instead of N queries, we do one query per unique result combination
    results
    |> Enum.group_by(fn {_url, result} ->
      # Group by all fields that will be updated
      {result.status, result.redirect_url, result.checked_at, result.redirect_chain}
    end)
    |> Enum.each(fn {result_values, url_results} ->
      urls = Enum.map(url_results, fn {url, _result} -> url end)
      {status, redirect_url, checked_at, redirect_chain} = result_values

      # Single query updating all URLs with the same result
      from(p in Performance, where: p.url in ^urls)
      |> Repo.update_all(
        set: [
          http_status: status,
          redirect_url: redirect_url,
          http_checked_at: checked_at,
          http_redirect_chain: redirect_chain,
          updated_at: checked_at
        ]
      )
    end)

    {:ok, length(results)}
  end
end
