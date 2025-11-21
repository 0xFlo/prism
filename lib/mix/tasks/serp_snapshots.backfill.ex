defmodule Mix.Tasks.SerpSnapshots.Backfill do
  @moduledoc """
  Runs the SERP snapshot enrichment backfill so historic rows gain the new
  competitor metadata, content-type classifications, and ScrapFly citation
  flags added in Story 2.

  ## Options

    * `--batch-size N` / `-b N` – rows per batch (default: 100)
    * `--limit N` / `-l N` – maximum rows to process (useful for rehearsals)
    * `--dry-run` / `-d` – report what would change without updating the DB
    * `--resume-after ISO8601` / `-r ISO8601` – skip rows inserted before the timestamp

  ## Examples

      # Standard execution with defaults
      mix serp_snapshots.backfill

      # Quick rehearsal of 250 rows (no writes)
      mix serp_snapshots.backfill --limit 250 --dry-run

      # Resume after a timestamp with smaller batches
      mix serp_snapshots.backfill --resume-after 2025-11-15T00:00:00Z --batch-size 50
  """

  use Mix.Task

  alias GscAnalytics.SerpSnapshots.Backfill

  @shortdoc "Backfills SERP snapshots with enriched competitor metadata"

  @switches [
    batch_size: :integer,
    limit: :integer,
    dry_run: :boolean,
    resume_after: :string
  ]
  @aliases [b: :batch_size, l: :limit, d: :dry_run, r: :resume_after]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    backfill_opts =
      opts
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    Mix.shell().info("""

    ╔════════════════════════════════════════════════════════════╗
    ║  SERP Snapshot Backfill                                    ║
    ╚════════════════════════════════════════════════════════════╝

    • Batch size:     #{display_opt(opts[:batch_size], 100)}
    • Limit:          #{display_opt(opts[:limit], "∞")}
    • Dry run:        #{opts[:dry_run] == true}
    • Resume after:   #{display_opt(opts[:resume_after], "not set")}

    Parsing stored ScrapFly HTML to normalize competitors/content types...
    """)

    case Backfill.run(backfill_opts) do
      {:ok, summary} ->
        print_summary(summary)

      {:error, reason} ->
        Mix.raise("SERP snapshot backfill failed: #{inspect(reason)}")
    end
  end

  defp display_opt(nil, default), do: default
  defp display_opt(value, _default), do: value

  defp print_summary(summary) do
    Mix.shell().info("""
    ╔════════════════════════════════════════════════════════════╗
    ║  Backfill Complete                                         ║
    ╚════════════════════════════════════════════════════════════╝

    🔁 Dry run:             #{summary.dry_run}
    📦 Batch size:          #{summary.batch_size}
    📈 Processed rows:      #{summary.total}
    ✏️  Updated rows:       #{summary.updated}
    ⏭️  Skipped rows:       #{summary.skipped}
    ⚠️  Recent errors:      #{length(summary.errors)}
    🕒 Last processed ID:   #{summary.last_processed_id || "n/a"}
    🕒 Last processed at:   #{summary.last_processed_at || "n/a"}

    #{error_lines(summary.errors)}
    """)
  end

  defp error_lines([]), do: "No errors reported."

  defp error_lines(errors) do
    (["Recent errors:"] ++ Enum.map(errors, &format_error/1))
    |> Enum.join("\n")
  end

  defp format_error(%{id: id, reason: reason}), do: "  • #{id}: #{reason}"
  defp format_error(other), do: "  • #{inspect(other)}"
end
