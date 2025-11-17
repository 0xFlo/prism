# T014: Manual Verification

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🟡 P2 Medium
**TDD Required:** No (manual testing)

## Description
Manual verification of the complete SERP integration with **acceptance criteria** (Codex requirement).

## Acceptance Criteria (Codex-Required)

### ScrapFly API Connectivity
- [ ] API call succeeds with valid keyword
- [ ] JSON response contains organic_results
- [ ] Rate limiter prevents excessive calls
- [ ] API cost tracking accurate (31 credits/query)

### Position Extraction
- [ ] Position extracted correctly for ranked URLs
- [ ] Returns nil for non-ranked URLs
- [ ] Competitors list accurate
- [ ] SERP features detected

### Oban Worker
- [ ] Job enqueued successfully
- [ ] Job processes without errors
- [ ] Snapshot saved to database
- [ ] Idempotency prevents duplicate jobs within 1 hour

### LiveView Integration
- [ ] "Check SERP" button visible (auth required)
- [ ] Button triggers job successfully
- [ ] Flash message confirms queueing
- [ ] Latest snapshot displays after check

### Data Pruning
- [ ] Old snapshots (>7 days) deleted
- [ ] Pruning worker runs on schedule
- [ ] Logs show deletion count

## Verification Steps

1. **Test ScrapFly API**
   ```elixir
   # In IEx
   iex> GscAnalytics.DataSources.SERP.Core.Client.scrape_google("elixir programming")
   {:ok, %{"result" => %{"organic_results" => [...]}}}
   ```

2. **Test Parser**
   ```elixir
   iex> response = GscAnalytics.DataSources.SERP.Core.Client.scrape_google("elixir")
   iex> GscAnalytics.DataSources.SERP.Core.Parser.parse_serp(response, "https://elixir-lang.org")
   %{position: 1, competitors: [...], serp_features: [...]}
   ```

3. **Test Oban Worker**
   ```elixir
   iex> {:ok, job} = GscAnalytics.Workers.SerpCheckWorker.new(%{
     property_id: "...",
     url: "https://scrapfly.io",
     keyword: "web scraping",
     account_id: 1
   }) |> Oban.insert()

   # Wait for job to process
   iex> Oban.check_queue(queue: :serp_check)
   ```

4. **Test LiveView (Browser)**
   - Navigate to URL detail page
   - Click "Check SERP Position"
   - Verify flash message
   - Refresh after 10-30 seconds
   - Verify position displayed

5. **Test Data Pruning**
   ```elixir
   iex> GscAnalytics.Workers.SerpPruningWorker.new(%{}) |> Oban.insert()
   # Check logs for deletion count
   ```

6. **Cost Tracking**
   ```elixir
   iex> Repo.aggregate(SerpSnapshot, :sum, :api_cost)
   # Verify total credits used
   ```

## Sample Test URLs

- **Elixir Lang:** https://elixir-lang.org (keyword: "elixir programming")
- **ScrapFly:** https://scrapfly.io (keyword: "web scraping api")
- **Phoenix Framework:** https://www.phoenixframework.org (keyword: "phoenix framework")

## Expected Results

| URL | Keyword | Expected Position | SERP Features |
|-----|---------|------------------|---------------|
| elixir-lang.org | elixir programming | 1-3 | featured_snippet |
| scrapfly.io | web scraping api | 1-5 | - |
| phoenixframework.org | phoenix framework | 1-3 | - |

## Definition of Done
- [ ] All acceptance criteria verified
- [ ] Sample URLs tested successfully
- [ ] Cost tracking accurate
- [ ] No errors in logs
- [ ] Ready for production

## Notes
- Use 1 million free ScrapFly credits for testing
- Test with realistic keywords (not obscure ones)
- Verify idempotency by clicking button twice rapidly

## 📚 Reference Documentation
- **Manual Testing Checklist:** [Testing Guide](/Users/flor/Developer/prism/docs/testing-quick-reference.md)
