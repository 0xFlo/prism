defmodule GscAnalytics.DataSources.Backlinks.Importers.AhrefsCSV do
  @moduledoc """
  Imports backlinks from Ahrefs Site Explorer export.

  ## ⚠️  EXTERNAL DATA SOURCE

  **Source**: Ahrefs backlink checker (manual export)
  **Format**: Comma-delimited CSV with quoted fields
  **Frequency**: Manual export and import as needed

  ## CSV Column Mapping (1-indexed)

  - Column 2: "Referring page URL" → `source_url`
  - Column 6: "Domain rating" → `domain_rating` (DR - SEO authority metric)
  - Column 8: "Domain traffic" → `domain_traffic` (estimated monthly organic traffic)
  - Column 14: "Target URL" → `target_url`
  - Column 16: "Anchor" → `anchor_text`
  - Column 30: "First seen" → `first_seen_at` (format: "YYYY-MM-DD HH:MM:SS")

  **Ignored columns**: Page title, UR, nofollow, UGC, sponsored, etc.

  ## Data Stored

  Only imports essential fields to keep schema simple:
  - target_url
  - source_url (extracted domain becomes source_domain)
  - anchor_text
  - first_seen_at

  ## CSV Parsing

  Uses NimbleCSV for proper handling of quoted fields. Ahrefs exports contain
  commas and quotes inside fields, so naive string splitting breaks parsing.

  ## Usage

      AhrefsCSV.import("scrapfly/ahrefs-backlink-report.csv")
      #=> {:ok, %{imported: 455, skipped: 0, errors: []}}
  """

  require Logger
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Backlink

  # Define CSV parser with proper quote handling
  NimbleCSV.define(AhrefsParser, separator: ",", escape: "\"")

  @batch_size 500
  @data_source "ahrefs"

  # Column indices (0-indexed)
  @col_source_url 1
  @col_domain_rating 5
  @col_domain_traffic 7
  @col_target_url 13
  @col_anchor 15
  @col_first_seen 29

  @doc """
  Import Ahrefs CSV file.

  Returns:
  - `{:ok, stats}` - Success with import statistics
  - `{:error, reason}` - Failure with error message

  ## Examples

      iex> import("scrapfly/ahrefs-backlink-report.csv")
      {:ok, %{imported: 455, skipped: 0, errors: [], batch_id: "..."}}
  """
  def import(csv_path) do
    unless File.exists?(csv_path) do
      {:error, "File not found: #{csv_path}"}
    else
      Logger.info("Starting Ahrefs CSV import: #{csv_path}")
      batch_id = Ecto.UUID.generate()
      start_time = System.monotonic_time(:millisecond)

      csv_path
      |> File.stream!()
      |> AhrefsParser.parse_stream(skip_headers: false)
      # Skip header row
      |> Stream.drop(1)
      |> Stream.map(&parse_row/1)
      # Filter out parse errors
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce({0, 0, []}, fn chunk, {imported, skipped, errors} ->
        {:ok, count} = insert_batch(chunk, batch_id)
        Logger.debug("Inserted batch: #{count} records")
        {imported + count, skipped, errors}
      end)
      |> then(fn {imported, skipped, errors} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info("""
        Ahrefs CSV import complete:
          - Imported: #{imported}
          - Skipped: #{skipped}
          - Errors: #{length(errors)}
          - Duration: #{duration}ms
          - Batch ID: #{batch_id}
        """)

        {:ok,
         %{
           imported: imported,
           skipped: skipped,
           errors: errors,
           batch_id: batch_id,
           duration_ms: duration
         }}
      end)
    end
  end

  # Parse a single CSV row (already parsed by NimbleCSV into list of fields)
  defp parse_row(row) when is_list(row) do
    try do
      # Extract columns by index
      source_url = Enum.at(row, @col_source_url, "")
      domain_rating = Enum.at(row, @col_domain_rating, "")
      domain_traffic = Enum.at(row, @col_domain_traffic, "")
      target_url = Enum.at(row, @col_target_url, "")
      anchor_text = Enum.at(row, @col_anchor, "")
      first_seen = Enum.at(row, @col_first_seen, "")

      # Skip rows with missing essential data
      if source_url == "" or target_url == "" do
        nil
      else
        %{
          source_url: String.trim(source_url),
          target_url: String.trim(target_url),
          anchor_text: String.trim(anchor_text),
          first_seen_at: parse_timestamp(first_seen),
          domain_rating: parse_integer(domain_rating),
          domain_traffic: parse_integer(domain_traffic),
          data_source: @data_source
        }
      end
    rescue
      e ->
        Logger.warning("Failed to parse row: #{inspect(e)}")
        nil
    end
  end

  # Parse integer field, returning nil if empty or invalid
  defp parse_integer(""), do: nil

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  # Parse Ahrefs timestamp format: "2025-01-06 11:17:48"
  defp parse_timestamp(timestamp_str) do
    timestamp_str = String.trim(timestamp_str)

    # Already in YYYY-MM-DD HH:MM:SS format, just need to add T and Z
    iso_string = timestamp_str |> String.replace(" ", "T") |> Kernel.<>("Z")

    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} ->
        datetime

      {:error, reason} ->
        Logger.warning("Failed to parse timestamp '#{timestamp_str}': #{inspect(reason)}")
        DateTime.utc_now()
    end
  end

  # Batch insert with conflict handling
  defp insert_batch(records, batch_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(records, fn record ->
        # Truncate first_seen_at as well
        first_seen_at =
          record.first_seen_at
          |> DateTime.truncate(:second)

        # Extract source_domain from source_url (since Repo.insert_all bypasses changesets)
        source_domain =
          record.source_url
          |> URI.parse()
          |> Map.get(:host)

        record
        |> Map.put(:source_domain, source_domain)
        |> Map.put(:first_seen_at, first_seen_at)
        |> Map.put(:import_batch_id, batch_id)
        |> Map.put(:imported_at, now)
        |> Map.put(:import_metadata, %{
          source: "ahrefs_csv",
          imported_by: "mix backlinks.import"
        })
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
        |> Map.put(:id, Ecto.UUID.generate())
      end)

    # Ahrefs data takes priority - update existing records with newer Ahrefs data
    {count, _} =
      Repo.insert_all(Backlink, entries,
        on_conflict:
          {:replace,
           [
             :domain_rating,
             :domain_traffic,
             :anchor_text,
             :first_seen_at,
             :data_source,
             :import_batch_id,
             :imported_at,
             :import_metadata,
             :updated_at
           ]},
        conflict_target: [:source_url, :target_url]
      )

    {:ok, count}
  end
end
