defmodule GscAnalytics.DataSources.GSC.Telemetry.AuditLogger do
  @moduledoc """
  Telemetry handler for GSC API audit logging.

  Writes structured JSON logs to logs/gsc_audit.log for API efficiency analysis.
  Each line is a JSON object containing event metadata, measurements, and timestamps.

  ## Usage

  Analyze logs with standard Unix tools:

      # Watch live API calls
      tail -f logs/gsc_audit.log

      # Count API calls
      grep "api.request" logs/gsc_audit.log | wc -l

      # Find rate-limited requests
      grep "rate_limited\":true" logs/gsc_audit.log

      # Summary with jq
      cat logs/gsc_audit.log | jq -s 'map(select(.event=="api.request")) | {total: length, avg_duration: (map(.duration_ms)|add/length)}'
  """

  require Logger

  @log_file "logs/gsc_audit.log"

  @doc """
  Attach telemetry handlers for GSC API events.
  Called during application startup.
  """
  def attach do
    events = [
      [:gsc_analytics, :api, :request],
      [:gsc_analytics, :sync, :complete],
      [:gsc_analytics, :auth, :token_refresh]
    ]

    :telemetry.attach_many(
      "gsc-audit-logger",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    ensure_log_directory()
    Logger.info("GSC audit logger attached - logging to #{@log_file}")
  end

  @doc """
  Telemetry event handler that writes JSON to audit log file.
  """
  def handle_event(event_name, measurements, metadata, _config) do
    event_type = event_name |> Enum.take(-2) |> Enum.join(".")

    log_entry = %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      event: event_type,
      measurements: measurements,
      metadata: metadata
    }

    # Write JSON line to log file
    json = JSON.encode!(log_entry)
    File.write!(@log_file, json <> "\n", [:append])
  rescue
    error ->
      Logger.error("Failed to write audit log: #{inspect(error)}")
  end

  @doc """
  Helper to emit API request telemetry events.
  Called from Client module after each API call.
  """
  def log_api_request(operation, measurements, metadata) do
    :telemetry.execute(
      [:gsc_analytics, :api, :request],
      Map.merge(%{duration_ms: 0, rows: 0}, measurements),
      Map.merge(%{operation: operation}, metadata)
    )
  end

  @doc """
  Helper to emit sync completion telemetry events.
  Called from Sync module after completing a date range sync.
  """
  def log_sync_complete(measurements, metadata) do
    :telemetry.execute(
      [:gsc_analytics, :sync, :complete],
      measurements,
      metadata
    )
  end

  @doc """
  Helper to emit authentication telemetry events.
  Called from Authenticator when token is refreshed.
  """
  def log_auth_event(event_type, metadata) do
    :telemetry.execute(
      [:gsc_analytics, :auth, :token_refresh],
      %{timestamp: System.system_time(:millisecond)},
      Map.put(metadata, :event_type, event_type)
    )
  end

  defp ensure_log_directory do
    log_dir = Path.dirname(@log_file)
    File.mkdir_p!(log_dir)
  end
end
