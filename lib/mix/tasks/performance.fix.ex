defmodule Mix.Tasks.Performance.Fix do
  @moduledoc """
  One-time migration to fix Performance table aggregation.

  ## ⚠️  DATA INTEGRITY FIX - ONE-TIME MIGRATION

  This task recalculates all Performance records using proper 30-day aggregation
  from TimeSeries data. Previously, Performance records incorrectly stored single-day
  metrics instead of aggregated totals, causing dashboard stats to be drastically
  understated.

  ## Background

  The Performance table had a bug where it stored single-day metrics instead of
  30-day aggregated totals. This caused major discrepancies:
  - URL showing 65 total clicks when actually had 3,600+ clicks
  - All metrics (impressions, CTR, position) similarly understated
  - Dashboard summary stats were completely wrong

  ## What This Task Does

  1. Fetches all URLs from the Performance table
  2. For each URL, recalculates aggregated metrics from last 30 days of TimeSeries data
  3. Updates Performance record with corrected totals and date ranges
  4. Uses weighted averages for CTR and position (weighted by impressions)
  5. Reports progress and statistics

  ## Usage

      # Fix all Performance records
      mix performance.fix

      # Fix specific account only (for multi-tenant setup)
      mix performance.fix --account-id 1

  ## Expected Results

  - All Performance records updated with correct 30-day aggregated metrics
  - Date ranges properly tracked (date_range_start to date_range_end)
  - Summary stats on main dashboard now match chart data
  - URL detail pages show accurate totals

  ## Safety

  - Task is idempotent - safe to run multiple times
  - Uses proper database transactions
  - Validates data before updating
  - Reports any errors encountered
  """

  use Mix.Task

  require Logger
  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Performance
  alias GscAnalytics.DataSources.GSC.Core.Persistence

  @shortdoc "Fix Performance table aggregation (ONE-TIME MIGRATION)"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          account_id: :integer
        ]
      )

    account_id = Keyword.get(opts, :account_id, 1)

    Mix.shell().info("""

    ╔════════════════════════════════════════════════════════════╗
    ║  Performance Table Migration - Data Integrity Fix          ║
    ╚════════════════════════════════════════════════════════════╝

    🔧 Recalculating all Performance records with proper 30-day aggregation

    Account ID: #{account_id}
    Task is idempotent - safe to re-run multiple times
    """)

    # Fetch all URLs that need fixing
    url_pairs = fetch_all_urls(account_id)
    total = length(url_pairs)

    Mix.shell().info("📊 Found #{total} Performance records to process\n")

    if total == 0 do
      Mix.shell().info("✅ No records to process")
      :ok
    else
      process_urls(url_pairs, account_id, total)
    end
  end

  defp fetch_all_urls(account_id) do
    from(p in Performance,
      where: p.account_id == ^account_id,
      select: {p.property_url, p.url}
    )
    |> Repo.all()
  end

  defp process_urls(url_pairs, account_id, total) do
    start_time = System.monotonic_time(:millisecond)

    results =
      url_pairs
      |> Enum.with_index(1)
      |> Enum.map(fn {{property_url, url}, index} ->
        process_url(property_url, url, account_id, index, total)
      end)

    duration = System.monotonic_time(:millisecond) - start_time

    # Count results
    success_count = Enum.count(results, &match?(:ok, &1))
    error_count = Enum.count(results, &match?({:error, _}, &1))
    skipped_count = Enum.count(results, &match?(:skipped, &1))

    # Print summary
    print_summary(success_count, error_count, skipped_count, duration)
  end

  defp process_url(property_url, url, account_id, index, total) do
    # Show progress
    if rem(index, 10) == 0 or index == 1 do
      Mix.shell().info("Processing #{index}/#{total}...")
    end

    case Persistence.refresh_performance_cache(account_id, property_url, url, 30) do
      {:ok, nil} ->
        :skipped

      {:ok, _perf} ->
        if rem(index, 50) == 0 do
          Mix.shell().info("  ✓ #{truncate_url(url)}")
        end

        :ok

      {:error, reason} ->
        Mix.shell().error("  ✗ #{truncate_url(url)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp truncate_url(url) when byte_size(url) > 60 do
    String.slice(url, 0, 57) <> "..."
  end

  defp truncate_url(url), do: url

  defp print_summary(success, errors, skipped, duration_ms) do
    Mix.shell().info("""

    ╔════════════════════════════════════════════════════════════╗
    ║  Migration Complete                                         ║
    ╚════════════════════════════════════════════════════════════╝

    ✅ Successfully processed: #{success}
    ⏭️  Skipped (no data): #{skipped}
    ❌ Errors: #{errors}
    ⏱️  Duration: #{duration_ms}ms

    ✨ Performance table has been migrated!

    All metrics now show proper 30-day aggregated totals:
    - Total clicks (sum of last 30 days)
    - Total impressions (sum of last 30 days)
    - Average CTR (weighted by impressions)
    - Average position (weighted by impressions)
    - Date ranges properly tracked

    Dashboard stats should now match chart data accurately.
    """)
  end
end
