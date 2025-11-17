# Ticket-006: GSC Sync Pipeline & Storage Updates

## Status: TODO
**Priority:** P1
**Estimate:** 1.5 days
**Dependencies:** ticket-002, ticket-003
**Blocks:** ticket-007

## Problem Statement
The sync pipeline (`DataSources.GSC.Core.Sync`) already accepts `site_url` as a parameter but assumes this comes from a single default property. We need to update it to work with the active property from the new multi-property system and ensure data is stored with proper `property_url` fields.

## Acceptance Criteria
- [ ] Sync functions use active property from `workspace_properties` table
- [ ] OAuth credentials continue to work at workspace level (no changes needed)
- [ ] Data stored with `property_url` field populated in all tables
- [ ] Audit logs include property context
- [ ] Sync refuses to run if no active property configured
- [ ] Backward compatibility maintained for existing sync jobs

## Implementation Plan

### 1. Update Sync Module to Use Active Property

**Note:** The existing sync already accepts `site_url` - we just need to ensure it gets the right property:

```elixir
# lib/gsc_analytics/data_sources/gsc/core/sync.ex

@doc """
Sync yesterday's data for the active property.
Requires workspace to have an active property configured.
"""
def sync_yesterday(site_url \\ nil, opts \\ []) do
  account_id = opts[:account_id] || Config.default_account_id()

  # Get active property if site_url not provided
  site_url =
    site_url ||
    case Accounts.get_active_property_url(account_id) do
      {:ok, url} -> url
      {:error, :no_active_property} ->
        Logger.error("No active property for account #{account_id}")
        raise "No active property configured. Please configure in Settings."
      {:error, reason} ->
        Logger.error("Failed to get property: #{inspect(reason)}")
        raise "Failed to get active property"
    end

  target_date = Date.add(Date.utc_today(), -Config.data_delay_days())

  sync_date_range(
    site_url,
    target_date,
    target_date,
    Keyword.put(opts, :account_id, account_id)
  )
end

@doc """
Sync a date range for a specific property or the active property.
"""
def sync_date_range(site_url, start_date, end_date, opts \\ []) do
  account_id = opts[:account_id] || Config.default_account_id()
  start_time = System.monotonic_time(:millisecond)

  # Validate property exists in our system
  unless property_exists?(account_id, site_url) do
    Logger.warning("Property #{site_url} not configured for account #{account_id}")
  end

  Logger.info("Starting GSC sync for #{site_url} from #{start_date} to #{end_date}")

  # Rest of existing implementation...
  # The sync already handles site_url correctly
end

defp property_exists?(account_id, site_url) do
  properties = Accounts.list_properties(account_id)
  Enum.any?(properties, &(&1.property_url == site_url))
end

# Helper for backward compatibility
defp get_default_site_url(account_id) do
  case Accounts.get_active_property_url(account_id) do
    {:ok, url} -> url
    {:error, _} ->
      # Fall back to legacy default_property
      case Accounts.gsc_default_property(account_id) do
        {:ok, url} -> url
        _ -> nil
      end
  end
end
```

### 2. Update Persistence Layer

The persistence module needs to ensure `property_url` is always stored:

```elixir
# lib/gsc_analytics/data_sources/gsc/core/persistence.ex

def persist_performance_data(account_id, site_url, data) do
  # Ensure property_url is included in all inserts
  timestamp = DateTime.utc_now()

  entries = Enum.map(data, fn row ->
    %{
      id: Ecto.UUID.generate(),  # Use binary_id for new records
      account_id: account_id,
      property_url: site_url,  # Critical: Always include property_url
      url: row["url"],
      clicks: row["clicks"] || 0,
      impressions: row["impressions"] || 0,
      ctr: row["ctr"] || 0.0,
      position: row["position"] || 0.0,
      inserted_at: timestamp,
      updated_at: timestamp
    }
  end)

  {inserted, _} = Repo.insert_all(Performance, entries,
    on_conflict: {:replace, [:clicks, :impressions, :ctr, :position, :property_url, :updated_at]},
    conflict_target: [:account_id, :url]  # Existing unique constraint
  )

  {:ok, inserted}
end

def persist_time_series_data(account_id, site_url, date, data) do
  timestamp = DateTime.utc_now()

  entries = Enum.map(data, fn row ->
    %{
      account_id: account_id,
      property_url: site_url,  # Critical: Always include property_url
      url: row["url"],
      date: date,
      period_type: "daily",
      clicks: row["clicks"] || 0,
      impressions: row["impressions"] || 0,
      ctr: row["ctr"] || 0.0,
      position: row["position"] || 0.0,
      data_available: true,
      inserted_at: timestamp
    }
  end)

  {inserted, _} = Repo.insert_all(TimeSeries, entries,
    on_conflict: {:replace, [:clicks, :impressions, :ctr, :position, :property_url]},
    conflict_target: [:account_id, :url, :date]  # Composite primary key
  )

  {:ok, inserted}
end
```

### 3. Update Sync Progress Tracking

```elixir
# lib/gsc_analytics/data_sources/gsc/support/sync_progress.ex

def start_sync(account_id, property_url \\ nil) do
  property_url = property_url || get_active_property_url(account_id)

  job = %{
    id: Ecto.UUID.generate(),
    account_id: account_id,
    property_url: property_url,  # Track which property is syncing
    status: :running,
    started_at: DateTime.utc_now(),
    progress: 0,
    total: 0
  }

  # Store in ETS or database
  :ets.insert(:sync_jobs, {job.id, job})

  # Broadcast to LiveView
  Phoenix.PubSub.broadcast(
    GscAnalytics.PubSub,
    "sync_progress",
    {:sync_started, job}
  )

  job.id
end

def update_progress(job_id, updates) do
  case :ets.lookup(:sync_jobs, job_id) do
    [{^job_id, job}] ->
      updated = Map.merge(job, updates)
      :ets.insert(:sync_jobs, {job_id, updated})

      Phoenix.PubSub.broadcast(
        GscAnalytics.PubSub,
        "sync_progress",
        {:sync_progress, updated}
      )

    _ ->
      :ok
  end
end
```

### 4. Update Telemetry/Audit Logging

```elixir
# lib/gsc_analytics/data_sources/gsc/telemetry/audit_logger.ex

def log_sync_event(event_type, metadata) do
  entry = %{
    event: event_type,
    account_id: metadata.account_id,
    property_url: metadata.property_url,  # Add property context
    timestamp: DateTime.utc_now(),
    metadata: metadata
  }

  # Log to file or database
  Logger.info("AUDIT: #{inspect(entry)}", audit: true)

  # Emit telemetry event
  :telemetry.execute(
    [:gsc_analytics, :sync, event_type],
    %{count: 1},
    %{
      account_id: metadata.account_id,
      property_url: metadata.property_url
    }
  )
end
```

### 5. Update Scheduled Jobs

If using Oban or similar for scheduled syncs:

```elixir
# lib/gsc_analytics/workers/daily_sync_worker.ex

def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
  case Accounts.get_active_property(account_id) do
    nil ->
      Logger.warning("Skipping sync for account #{account_id}: no active property")
      {:ok, :skipped}

    property ->
      Sync.sync_yesterday(property.property_url, account_id: account_id)
      {:ok, :synced}
  end
end
```

### 6. Migration Helper for Existing Data

```elixir
@doc """
One-time migration to populate property_url in existing data.
Run after deploying the new schema changes.
"""
def migrate_existing_data do
  Accounts.list_gsc_accounts()
  |> Enum.each(fn account ->
    case Accounts.get_active_property_url(account.id) do
      {:ok, property_url} ->
        # Update time_series
        from(ts in TimeSeries,
          where: ts.account_id == ^account.id and is_nil(ts.property_url)
        )
        |> Repo.update_all(set: [property_url: property_url])

        # Update performance
        from(p in Performance,
          where: p.account_id == ^account.id and is_nil(p.property_url)
        )
        |> Repo.update_all(set: [property_url: property_url])

        Logger.info("Migrated data for account #{account.id} to property #{property_url}")

      _ ->
        Logger.warning("No default property for account #{account.id}, skipping migration")
    end
  end)
end
```

## Testing Notes
- Mock `Client.search_analytics_query/4` to return test data
- Test sync with active property vs explicit property_url
- Verify `property_url` is stored in all data tables
- Test sync failure when no active property configured
- Verify audit logs include property_url field
- Test backward compatibility with existing sync jobs
- Test scheduled jobs handle missing properties gracefully

## Performance Considerations
- Ensure composite indexes on (account_id, property_url) exist
- Monitor sync performance with multiple properties
- Consider batching inserts for large datasets
- Use EXPLAIN ANALYZE on data queries to verify index usage