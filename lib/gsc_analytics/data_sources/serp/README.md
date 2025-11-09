# SERP Data Source

ScrapFly API integration for real-time SERP position checking.

## Structure

- **core/** - Main business logic (Client, Parser, Persistence, Config)
- **support/** - Infrastructure services (RateLimiter, RetryHelper)
- **telemetry/** - Observability (AuditLogger)

## Usage

```elixir
# Check SERP position for a URL
GscAnalytics.DataSources.SERP.Core.Client.scrape_google("test query")
```

## Configuration

Set the following environment variables:

- `SCRAPFLY_API_KEY` - Your ScrapFly API key (required)

```bash
export SCRAPFLY_API_KEY="your_api_key_here"
```
