# T013: Data Pruning Worker

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** No (maintenance worker)

## Description
Create Oban worker to automatically delete SERP snapshots older than 7 days (Codex requirement).

## Acceptance Criteria
- [ ] Oban worker deletes snapshots > 7 days old
- [ ] Runs daily via cron schedule
- [ ] Logs number of records deleted
- [ ] Efficient query using :checked_at index

## Implementation

```elixir
# lib/gsc_analytics/workers/serp_pruning_worker.ex
defmodule GscAnalytics.Workers.SerpPruningWorker do
  use Oban.Worker,
    queue: :maintenance,
    priority: 3

  import Ecto.Query
  alias GscAnalytics.Repo
  alias GscAnalytics.Schemas.SerpSnapshot

  @retention_days 7

  @impl Oban.Worker
  def perform(_job) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-@retention_days, :day)

    {count, _} =
      from(s in SerpSnapshot, where: s.checked_at < ^cutoff_date)
      |> Repo.delete_all()

    IO.puts("Deleted #{count} SERP snapshots older than #{@retention_days} days")

    :ok
  end
end
```

Add cron schedule to config:
```elixir
# config/config.exs
config :gsc_analytics, Oban,
  queues: [
    default: 10,
    gsc_sync: 1,
    serp_check: 3,
    maintenance: 1
  ],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"0 2 * * *", GscAnalytics.Workers.SerpPruningWorker}  # 2 AM daily
     ]}
  ]
```

## Definition of Done
- [ ] Worker deletes old snapshots
- [ ] Cron schedule configured
- [ ] Logging implemented
- [ ] Manual test successful

## 📚 Reference Documentation
- **Oban Cron:** [Reference Guide](/Users/flor/Developer/prism/docs/OBAN_REFERENCE.md)
- **Cron Scheduling:** [Scheduling Guide](/Users/flor/Developer/prism/docs/cron-scheduling-research.md)
