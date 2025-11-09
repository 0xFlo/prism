# T002: ScrapFly Config & Env Setup

**Status:** 🔵 Not Started
**Story Points:** 1
**Priority:** 🔥 P1 Critical
**TDD Required:** No (configuration setup)

## Description
Configure ScrapFly API credentials and create the Config module for centralized configuration management.

## Acceptance Criteria
- [ ] SCRAPFLY_API_KEY environment variable configured in runtime.exs
- [ ] Core.Config module created with API key accessor
- [ ] Default configuration values documented
- [ ] Config module follows GSC.Core.Config pattern

## Implementation Steps

1. **Add to config/runtime.exs**
   ```elixir
   # ScrapFly SERP API Configuration
   config :gsc_analytics,
     scrapfly_api_key: System.get_env("SCRAPFLY_API_KEY")
   ```

2. **Create Core.Config module**
   ```elixir
   # lib/gsc_analytics/data_sources/serp/core/config.ex
   defmodule GscAnalytics.DataSources.SERP.Core.Config do
     @moduledoc """
     Centralized configuration for SERP data source.
     """

     def api_key do
       Application.get_env(:gsc_analytics, :scrapfly_api_key) ||
         raise "SCRAPFLY_API_KEY not configured"
     end

     def base_url, do: "https://api.scrapfly.io"

     def default_geo, do: "us"

     def default_format, do: "json"

     def rate_limit_per_minute, do: 60

     def unique_period_hours, do: 1
   end
   ```

3. **Update .env.example (if exists)**
   ```bash
   echo "SCRAPFLY_API_KEY=your_api_key_here" >> .env.example
   ```

4. **Document in README**
   Update `/lib/gsc_analytics/data_sources/serp/README.md`:
   ```markdown
   ## Configuration

   Set the following environment variables:

   - `SCRAPFLY_API_KEY` - Your ScrapFly API key (required)

   ```bash
   export SCRAPFLY_API_KEY="your_api_key_here"
   ```
   ```

## Testing

```elixir
# test/gsc_analytics/data_sources/serp/core/config_test.exs
defmodule GscAnalytics.DataSources.SERP.Core.ConfigTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.Config

  describe "api_key/0" do
    test "returns configured API key" do
      # Requires SCRAPFLY_API_KEY to be set in test env
      assert is_binary(Config.api_key())
    end
  end

  test "base_url/0 returns ScrapFly API URL" do
    assert Config.base_url() == "https://api.scrapfly.io"
  end

  test "default_geo/0 returns US" do
    assert Config.default_geo() == "us"
  end
end
```

## Definition of Done
- [ ] SCRAPFLY_API_KEY configured in runtime.exs
- [ ] Core.Config module created
- [ ] Tests pass
- [ ] Documentation updated
- [ ] Ready for HTTP client implementation

## Notes
- API key should never be committed to git
- Follow GSC.Core.Config pattern for consistency
- Config module provides single source of truth

## 📚 Reference Documentation
- **Environment Config:** [Guide](/Users/flor/Developer/prism/ENVIRONMENT_CONFIG_RESEARCH.md)
- **Example:** `lib/gsc_analytics/data_sources/gsc/core/config.ex`
- **ScrapFly Docs:** https://scrapfly.io/docs/scrape-api/getting-started
