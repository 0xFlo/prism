defmodule Mix.Tasks.Backlinks.Import do
  @moduledoc """
  Import backlinks from external CSV reports.

  ## ⚠️  MANUAL EXTERNAL DATA IMPORT

  This task imports backlink data from vendor and tool exports.
  Data does NOT auto-refresh - you must re-run imports manually when new reports arrive.

  ## Usage

      # Import both sources (auto-discovers CSVs in scrapfly/ directory)
      mix backlinks.import

      # Import specific source only
      mix backlinks.import --source vendor
      mix backlinks.import --source ahrefs

      # Custom file paths
      mix backlinks.import --vendor-csv path/to/vendor-report.csv
      mix backlinks.import --ahrefs-csv path/to/ahrefs-export.csv

  ## Default File Locations

  - Vendor: `scrapfly/backlinks-report.csv`
  - Ahrefs: `scrapfly/ahrefs-backlink-report.csv`

  ## Expected Results

  - Vendor CSV: ~466 purchased backlinks
  - Ahrefs CSV: ~455 discovered backlinks
  - Total: ~921 backlinks across Scrapfly blog URLs

  ## Data Sources

  - **vendor**: Purchased links from link building campaigns
  - **ahrefs**: Backlinks discovered via Ahrefs Site Explorer

  ## Output

  The task reports:
  - Records imported per source
  - Duplicates skipped (upsert logic prevents duplication)
  - Parse errors encountered
  - Data staleness warning if last import >90 days old
  """

  use Mix.Task

  require Logger
  alias GscAnalytics.DataSources.Backlinks.Backlink

  @shortdoc "Import backlinks from external CSV reports (MANUAL DATA)"

  @default_vendor_path "scrapfly/backlinks-report.csv"
  @default_ahrefs_path "scrapfly/ahrefs-backlink-report.csv"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          source: :string,
          vendor_csv: :string,
          ahrefs_csv: :string
        ]
      )

    source_filter = Keyword.get(opts, :source)
    vendor_path = Keyword.get(opts, :vendor_csv, @default_vendor_path)
    ahrefs_path = Keyword.get(opts, :ahrefs_csv, @default_ahrefs_path)

    Mix.shell().info("""

    ╔════════════════════════════════════════════════════════════╗
    ║  Backlinks Import - Manual External Data                   ║
    ╚════════════════════════════════════════════════════════════╝

    ⚠️  This imports data from EXTERNAL SOURCES (vendors/tools)
    Data does not auto-refresh - manual import required

    """)

    results = %{}

    # Import vendor CSV
    results =
      if should_import?("vendor", source_filter) do
        Mix.shell().info("\n📥 Importing Vendor CSV...")
        Mix.shell().info("   File: #{vendor_path}")

        result = import_with_progress(vendor_path, :vendor)
        Map.put(results, :vendor, result)
      else
        results
      end

    # Import Ahrefs CSV
    results =
      if should_import?("ahrefs", source_filter) do
        Mix.shell().info("\n📥 Importing Ahrefs CSV...")
        Mix.shell().info("   File: #{ahrefs_path}")

        result = import_with_progress(ahrefs_path, :ahrefs)
        Map.put(results, :ahrefs, result)
      else
        results
      end

    # Print summary
    print_summary(results)

    # Check data staleness
    check_staleness()
  end

  defp should_import?(_source, nil), do: true
  defp should_import?(source, filter), do: source == filter

  defp import_with_progress(path, :vendor) do
    case Backlink.import_vendor_csv(path) do
      {:ok, stats} ->
        Mix.shell().info("   ✅ Imported: #{stats.imported}")
        Mix.shell().info("   ⏭️  Skipped: #{stats.skipped}")

        if length(stats.errors) > 0 do
          Mix.shell().error("   ❌ Errors: #{length(stats.errors)}")
        end

        Mix.shell().info("   ⏱️  Duration: #{stats.duration_ms}ms")
        Mix.shell().info("   🆔 Batch ID: #{stats.batch_id}")
        {:ok, stats}

      {:error, reason} ->
        Mix.shell().error("   ❌ Import failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp import_with_progress(path, :ahrefs) do
    case Backlink.import_ahrefs_csv(path) do
      {:ok, stats} ->
        Mix.shell().info("   ✅ Imported: #{stats.imported}")
        Mix.shell().info("   ⏭️  Skipped: #{stats.skipped}")

        if length(stats.errors) > 0 do
          Mix.shell().error("   ❌ Errors: #{length(stats.errors)}")
        end

        Mix.shell().info("   ⏱️  Duration: #{stats.duration_ms}ms")
        Mix.shell().info("   🆔 Batch ID: #{stats.batch_id}")
        {:ok, stats}

      {:error, reason} ->
        Mix.shell().error("   ❌ Import failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp print_summary(results) do
    total_imported =
      results
      |> Map.values()
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, stats} -> stats.imported end)
      |> Enum.sum()

    Mix.shell().info("""

    ╔════════════════════════════════════════════════════════════╗
    ║  Import Complete                                            ║
    ╚════════════════════════════════════════════════════════════╝

    📊 Total Records Imported: #{total_imported}

    """)

    # Show summary stats
    case Backlink.summary_stats() do
      %{} = stats ->
        Mix.shell().info("📈 Backlink Database Summary:")
        Mix.shell().info("   • Total Backlinks: #{stats.total_backlinks}")
        Mix.shell().info("   • Unique Target URLs: #{stats.unique_targets}")
        Mix.shell().info("   • Unique Source Domains: #{stats.unique_sources}")

        if not Enum.empty?(stats.data_sources) do
          Mix.shell().info("\n   By Source:")

          Enum.each(stats.data_sources, fn {source, count} ->
            Mix.shell().info("     - #{source}: #{count}")
          end)
        end
    end
  end

  defp check_staleness do
    case Backlink.last_import_timestamp() do
      nil ->
        Mix.shell().info("\n⚠️  No backlink data found")

      last_import ->
        days_old = DateTime.diff(DateTime.utc_now(), last_import, :day)

        cond do
          days_old > 90 ->
            Mix.shell().error("""

            ⚠️  WARNING: Backlink data is STALE (#{days_old} days old)
            Last import: #{Calendar.strftime(last_import, "%Y-%m-%d %H:%M UTC")}

            Consider refreshing with new reports from vendors/Ahrefs
            """)

          days_old > 30 ->
            Mix.shell().info("""

            ℹ️  Backlink data is #{days_old} days old
            Last import: #{Calendar.strftime(last_import, "%Y-%m-%d %H:%M UTC")}
            """)

          true ->
            Mix.shell().info("""

            ✅ Backlink data is fresh (#{days_old} days old)
            Last import: #{Calendar.strftime(last_import, "%Y-%m-%d %H:%M UTC")}
            """)
        end
    end
  end
end
