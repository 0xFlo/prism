defmodule GscAnalytics.DataSources.Backlinks.Importers.VendorCSV do
  @moduledoc """
  Imports backlinks from vendor link building campaign reports.

  ## ⚠️  EXTERNAL DATA SOURCE

  **Source**: Purchased links vendor (manual report delivery)
  **Format**: Semicolon-delimited CSV
  **Frequency**: Manual import when reports received

  ## CSV Column Mapping

  1. Domain (source domain - extracted from URL instead)
  2. DR (domain rating - not imported)
  3. Traffic (domain traffic - not imported)
  4. **"The article you did link insertions on"** → `source_url`
  5. **"scrapfly.io URL"** → `target_url`
  6. **"Anchor text"** → `anchor_text`
  7. **"Timestamp"** → `first_seen_at` (format: "M/D/YYYY H:MM:SS")
  8. Month (not imported)

  ## Data Stored

  Only imports essential fields to keep schema simple:
  - target_url
  - source_url (extracted domain becomes source_domain)
  - anchor_text
  - first_seen_at
  - domain_rating and domain_traffic set to nil (vendor CSV doesn't include these)

  **Note**: When the same backlink exists in both vendor and Ahrefs exports,
  Ahrefs data takes precedence due to import order (vendor first, then Ahrefs
  with update-on-conflict).

  ## CSV Parsing

  Uses NimbleCSV for proper handling of semicolon-delimited fields.

  ## Usage

      VendorCSV.import("scrapfly/backlinks-report.csv")
      #=> {:ok, %{imported: 466, skipped: 0, errors: []}}
  """

  require Logger
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.Backlink

  # Define CSV parser with semicolon delimiter
  NimbleCSV.define(VendorParser, separator: ";", escape: "\"")

  @batch_size 500
  @data_source "vendor"

  @doc """
  Import vendor CSV file.

  Returns:
  - `{:ok, stats}` - Success with import statistics
  - `{:error, reason}` - Failure with error message

  ## Examples

      iex> import("scrapfly/backlinks-report.csv")
      {:ok, %{imported: 466, skipped: 0, errors: [], batch_id: "..."}}
  """
  def import(csv_path) do
    unless File.exists?(csv_path) do
      {:error, "File not found: #{csv_path}"}
    else
      Logger.info("Starting vendor CSV import: #{csv_path}")
      batch_id = Ecto.UUID.generate()
      start_time = System.monotonic_time(:millisecond)

      csv_path
      |> File.stream!()
      |> VendorParser.parse_stream(skip_headers: false)
      # Skip header row
      |> Stream.drop(1)
      |> Stream.map(&parse_row/1)
      # Filter out parse errors
      |> Stream.reject(&is_nil/1)
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce({0, 0, []}, fn chunk, {imported, skipped, errors} ->
        case insert_batch(chunk, batch_id) do
          {:ok, count} ->
            Logger.debug("Inserted batch: #{count} records")
            {imported + count, skipped, errors}

          {:error, reason} ->
            Logger.warning("Batch insert failed: #{inspect(reason)}")
            {imported, skipped + length(chunk), [reason | errors]}
        end
      end)
      |> then(fn {imported, skipped, errors} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info("""
        Vendor CSV import complete:
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
      # Skip rows with insufficient columns
      if length(row) < 7 do
        nil
      else
        # Extract relevant columns (indices 3, 4, 5, 6)
        [_domain, _dr, _traffic, source_url, target_url, anchor_text, timestamp | _rest] = row

        %{
          source_url: String.trim(source_url),
          target_url: String.trim(target_url),
          anchor_text: String.trim(anchor_text),
          first_seen_at: parse_timestamp(timestamp),
          data_source: @data_source
        }
      end
    rescue
      e ->
        Logger.debug("Failed to parse row: #{inspect(e)}")
        nil
    end
  end

  # Parse vendor timestamp format: "5/14/2024 18:06:49"
  defp parse_timestamp(timestamp_str) do
    timestamp_str = String.trim(timestamp_str)

    # Parse M/D/YYYY H:M:S format
    case String.split(timestamp_str, " ") do
      [date_part, time_part] ->
        [month, day, year] = String.split(date_part, "/")
        [hour, minute, second] = String.split(time_part, ":")

        # Pad with zeros
        month = String.pad_leading(month, 2, "0")
        day = String.pad_leading(day, 2, "0")
        hour = String.pad_leading(hour, 2, "0")
        minute = String.pad_leading(minute, 2, "0")
        second = String.pad_leading(second, 2, "0")

        iso_string = "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"

        case DateTime.from_iso8601(iso_string) do
          {:ok, datetime, _offset} ->
            datetime

          {:error, reason} ->
            Logger.warning("Failed to parse timestamp '#{timestamp_str}': #{inspect(reason)}")
            DateTime.utc_now()
        end

      _ ->
        Logger.warning("Invalid timestamp format '#{timestamp_str}'")
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
        |> Map.put(:domain_rating, nil)
        |> Map.put(:domain_traffic, nil)
        |> Map.put(:import_batch_id, batch_id)
        |> Map.put(:imported_at, now)
        |> Map.put(:import_metadata, %{
          source: "vendor_csv",
          imported_by: "mix backlinks.import"
        })
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
        |> Map.put(:id, Ecto.UUID.generate())
      end)

    case Repo.insert_all(Backlink, entries, on_conflict: :nothing) do
      {count, _} -> {:ok, count}
      error -> {:error, error}
    end
  end
end
