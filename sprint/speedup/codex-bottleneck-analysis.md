# Codex Bottleneck Analysis

**Date**: 2025-11-13
**Tool**: OpenAI Codex v0.57.0
**Model**: gpt-5-codex
**Reasoning Effort**: High

---

## Analysis Request

Analyze the GSC sync implementation for performance bottlenecks. The user reports it's slow despite having batch processing. Key files to examine:
- `lib/gsc_analytics/data_sources/gsc/core/sync/url_phase.ex`
- `lib/gsc_analytics/data_sources/gsc/core/sync/query_phase.ex`
- `lib/gsc_analytics/data_sources/gsc/core/persistence.ex`
- `lib/gsc_analytics/data_sources/gsc/support/batch_processor.ex`

Identify the top 3 bottlenecks and recommend specific optimizations with expected speedup impact.

---

## Findings

### Bottleneck #1: Sequential HTTP Batch Processing

**Location**:
- `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex:204-259`
- `lib/gsc_analytics/data_sources/gsc/support/batch_processor.ex:46-78`

**Problem**:
The paginator pulls at most `batch_size` (default 8) requests, sends them through a single call to `Client.fetch_query_batch/3`, waits for the response, then repeats. Because `BatchProcessor.execute_batch/4` serializes each chunk, there is never more than one HTTP batch in flight, and each batch contains far fewer than the 100 requests Google allows. Network latency therefore accumulates linearly with the number of `(date, start_row)` pairs even though the code is "batched".

**Optimization**:
Raise the per-batch payload to the API limit (e.g. send 50–80 requests per HTTP call) and/or run several HTTP batches concurrently via `Task.async_stream` or a GenStage pipeline so the next batch is issued while the current one is being parsed.

**Expected Impact**:
On the backfills we've profiled (~400 request pages at ~350 ms RTT) this would cut the query phase from ~140 s to ~18–35 s (4–8× improvement) depending on the degree of concurrency tolerated by the rate limiter.

**Status**:
- ✅ Batch size increased to 50 (Phase 1 completed)
- ⏸️ Concurrent batches blocked by state machine design (Phase 4)

---

### Bottleneck #2: Buffered Persistence

**Location**:
- `lib/gsc_analytics/data_sources/gsc/support/query_paginator.ex:333-430`
- `lib/gsc_analytics/data_sources/gsc/core/sync/query_phase.ex:61-107`
- `lib/gsc_analytics/data_sources/gsc/core/persistence.ex:176-238`

**Problem**:
For each date we append every 25 k-row page into `row_chunks`, and we only flatten and hand the entire list to `Persistence.process_query_response/4` once the **last** page arrives. This forces us to buffer hundreds of thousands of rows per busy day, perform O(n log n) grouping/sorting on the entire set at once, and block the paginator from issuing the next API batch while `process_query_response/4` rewrites the DB.

**Optimization**:
Emit the callback per page (or after a small number of pages), letting persistence write and aggregate incrementally. We can still compute the top 20 queries per URL by maintaining running heaps per URL instead of re-sorting whole lists. Streaming persistence would keep memory roughly proportional to a single page and overlap DB write time with the next HTTP fetch.

**Expected Impact**:
Typically halves end-to-end latency for high-volume properties while eliminating GC spikes.

**Estimated Speedup**: 1.5-2x

**Status**: 🟡 Ready to implement (Phase 2)

---

### Bottleneck #3: Synchronous Lifetime Stats Refresh

**Location**:
- `lib/gsc_analytics/data_sources/gsc/core/sync/url_phase.ex:36-108`
- `lib/gsc_analytics/data_sources/gsc/core/persistence.ex:120-327`

**Problem**:
Every URL batch waits for two heavyweight synchronous tasks: upserting all time-series rows **and** recomputing lifetime aggregates via `refresh_lifetime_stats_incrementally/3`, which deletes and re-inserts stats by scanning *all historical rows* for every URL touched that day. Because `URLPhase.fetch_and_store/3` processes dates sequentially, the next API call cannot start until this refresh finishes, so a property with 150 days × 2 s refresh/day burns five minutes purely on repeated aggregate rebuilds.

**Optimization**:
Decouple lifetime refresh from the hot path—queue the distinct URLs for a background worker or update the `url_lifetime_stats` table incrementally with `INSERT … ON CONFLICT DO UPDATE` so each day only touches the new slice. Deferring/streaming the refresh typically shrinks the URL phase wall time by 3–5× on large imports and frees DB I/O for the query stage.

**Expected Impact**: 3-5x speedup on large imports, 1.5-2x on typical syncs

**Status**:
- ✅ DELETE+INSERT replaced with UPSERT (Phase 1)
- 🟡 Ready to defer to end-of-sync (Phase 3)

---

## Next Steps

1. **Prototype a concurrent query fetcher** (higher per-batch payload + async batches) gated by a config flag to validate quota impact.
2. **Rework the paginator callback** to stream per page (or per small chunk) and adjust `Persistence.process_query_response/4` to handle incremental top-20 aggregation.
3. **Move lifetime-stat refresh** into an async worker or incremental-upsert path, ensuring URL ingestion only does the raw inserts.

---

## Performance Projections

### Phase 1 (Completed)
- Batch size: 8 → 50
- DELETE+INSERT → UPSERT
- **Expected**: 2-3x speedup
- **Actual**: TBD (needs production validation)

### Phase 2 (Streaming Persistence)
- **Expected**: Additional 1.5-2x speedup
- **Total**: 3-6x faster than original

### Phase 3 (Deferred Refresh)
- **Expected**: Additional 1.5-2x speedup
- **Total**: 4.5-12x theoretical, realistic 3-5x

### Phase 4 (Concurrent Batches)
- **Expected**: Additional 4-8x speedup
- **Total**: 12-60x theoretical
- **Blocker**: Requires state machine refactoring

---

## Code References

### Sequential Batch Processing
```elixir
# query_paginator.ex:204-259
defp do_paginated_fetch(account_id, site_url, batch_size, client, operation, dimensions, %{queue: queue} = state) do
  if :queue.is_empty(queue) do
    {:ok, finalize_results(state), state.total_api_calls, state.http_batch_calls}
  else
    {batch, remaining_queue} = take_batch(state.queue, batch_size, state.completed, [])
    # ... builds requests, calls client.fetch_query_batch (WAITS)
    # ... then recurses
  end
end
```

### Buffered Persistence
```elixir
# query_paginator.ex:333-430
defp process_successful_response(date, start_row, part, state) do
  rows = extract_rows(part)
  # Appends to row_chunks, only processes when complete
  updated_entry = result_entry |> Map.update!(:row_chunks, fn chunks -> [rows | chunks] end)
  # ... eventually flattens entire list and sorts
end
```

### Synchronous Lifetime Refresh
```elixir
# persistence.ex:277-326 (OLD - before UPSERT)
defp refresh_url_batch(account_id, property_url, urls, _batch_num, _total_batches) do
  Repo.transaction(fn ->
    # DELETE all existing stats
    Repo.query!("DELETE FROM url_lifetime_stats WHERE ...", [account_id, property_url, urls])
    # Re-INSERT by scanning all historical rows
    Repo.query!("INSERT INTO url_lifetime_stats (...) SELECT ... FROM gsc_time_series ...", [...])
  end)
end
```

---

## Token Usage
**Total tokens**: 112,334
