# T006: ScrapFly LLM Extraction (TDD)

**Status:** 🔵 Not Started
**Story Points:** 2
**Priority:** 🔥 P1 Critical
**TDD Required:** ✅ Yes

## Description
Use ScrapFly's LLM Extraction (`extraction_prompt`) to extract SERP position from Google search results. **Simpler than building custom parser** (recommended approach from ScrapFly docs).

## Acceptance Criteria
- [ ] TDD: RED → GREEN → REFACTOR phases completed
- [ ] Uses `extraction_prompt` parameter with natural language instructions
- [ ] Extracts position for target URL
- [ ] Extracts top 10 competitors
- [ ] Detects SERP features
- [ ] Handles URL not found in results
- [ ] Cost: 5 credits per query (LLM prompt pricing)

## Why LLM Extraction vs Custom Parser?

**Benefits:**
- ✅ Simpler implementation (no complex parsing logic)
- ✅ Handles Google SERP format changes automatically
- ✅ Natural language instructions (maintainable)
- ✅ Same cost as AI model (5 credits)
- ✅ Returns structured JSON

**From ScrapFly docs:**
> "Large Language Model extraction allows you to extract data from web pages using natural language instructions. You can describe the data you want to extract in plain English, and our models will handle the rest."

## TDD Workflow

### 🔴 RED Phase: Write Failing Tests First

```elixir
# test/gsc_analytics/data_sources/serp/core/llm_extractor_test.exs
defmodule GscAnalytics.DataSources.SERP.Core.LLMExtractorTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.LLMExtractor

  describe "build_extraction_prompt/1" do
    test "creates natural language prompt for SERP extraction" do
      url = "https://example.com"

      prompt = LLMExtractor.build_extraction_prompt(url)

      assert prompt =~ "Extract the position"
      assert prompt =~ url
      assert prompt =~ "JSON"
    end
  end

  describe "parse_llm_response/2" do
    test "extracts position from LLM JSON response" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "content_type" => "application/json",
            "data" => %{
              "position" => 3,
              "competitors" => [
                %{"position" => 1, "url" => "https://competitor1.com", "title" => "Title 1"},
                %{"position" => 2, "url" => "https://competitor2.com", "title" => "Title 2"}
              ],
              "serp_features" => ["featured_snippet"]
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert result.position == 3
      assert length(result.competitors) == 2
      assert "featured_snippet" in result.serp_features
    end

    test "returns nil position when URL not found" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => nil,
              "message" => "URL not found in search results"
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://notfound.com")

      assert is_nil(result.position)
    end

    test "handles malformed LLM response gracefully" do
      llm_response = %{"result" => %{}}

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert is_nil(result.position)
      assert result.competitors == []
    end
  end
end
```

**Run tests to confirm they FAIL:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/llm_extractor_test.exs
# Expected: All tests fail (module doesn't exist)
```

### 🟢 GREEN Phase: Minimal Implementation

```elixir
# lib/gsc_analytics/data_sources/serp/core/llm_extractor.ex
defmodule GscAnalytics.DataSources.SERP.Core.LLMExtractor do
  @moduledoc """
  Extract SERP position using ScrapFly's LLM Extraction.

  Uses `extraction_prompt` parameter instead of custom parsing.
  Cost: 5 API credits per query.
  """

  @doc """
  Build natural language prompt for SERP extraction.

  ## Example Prompt
  ```
  Extract the following information from these Google search results in JSON format:
  1. The position (1-100) where the URL 'https://example.com' appears
  2. The top 10 competing URLs with their positions and titles
  3. Any SERP features present (featured_snippet, people_also_ask, local_pack, etc.)

  Return format:
  {
    "position": 3 or null if not found,
    "competitors": [{"position": 1, "url": "...", "title": "..."}],
    "serp_features": ["featured_snippet"]
  }
  ```
  """
  def build_extraction_prompt(target_url) do
    """
    Extract the following information from these Google search results in JSON format:
    1. The position (1-100) where the URL '#{target_url}' appears in organic results
    2. The top 10 competing URLs with their positions and titles
    3. Any SERP features present (featured_snippet, people_also_ask, local_pack, video_carousel, image_pack)

    Return strictly valid JSON in this format:
    {
      "position": 3,
      "competitors": [
        {"position": 1, "url": "https://competitor.com", "title": "Page Title"}
      ],
      "serp_features": ["featured_snippet"]
    }

    If the target URL is not found, return position as null.
    """
  end

  @doc """
  Parse LLM extraction response from ScrapFly API.

  ## ScrapFly Response Structure
  ```json
  {
    "result": {
      "extracted_data": {
        "content_type": "application/json",
        "data": {
          "position": 3,
          "competitors": [...],
          "serp_features": [...]
        }
      }
    }
  }
  ```
  """
  def parse_llm_response(scrapfly_response, _target_url) do
    # Extract nested data from ScrapFly response structure
    extracted_data = get_in(scrapfly_response, ["result", "extracted_data", "data"])

    case extracted_data do
      nil ->
        # LLM didn't return expected structure
        %{
          position: nil,
          competitors: [],
          serp_features: [],
          parsed_at: DateTime.utc_now(),
          error: "No extracted data from LLM"
        }

      data when is_map(data) ->
        %{
          position: data["position"],
          competitors: data["competitors"] || [],
          serp_features: data["serp_features"] || [],
          parsed_at: DateTime.utc_now()
        }

      _ ->
        # Unexpected data format
        %{
          position: nil,
          competitors: [],
          serp_features: [],
          parsed_at: DateTime.utc_now(),
          error: "Invalid LLM response format"
        }
    end
  end
end
```

**Run tests to confirm they PASS:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/llm_extractor_test.exs
# Expected: All tests pass
```

### 🔵 REFACTOR Phase: Clean Up

1. Extract constants for prompt template
2. Add better error messages
3. Improve documentation
4. Add telemetry

```elixir
# Refactored version
defmodule GscAnalytics.DataSources.SERP.Core.LLMExtractor do
  @moduledoc """
  Extract SERP position using ScrapFly's LLM Extraction API.

  This approach uses natural language instructions instead of custom parsers,
  making it resilient to Google SERP format changes.

  ## Cost
  - 5 API credits per query (LLM prompt pricing)

  ## Example Usage
  ```elixir
  # Build prompt
  prompt = LLMExtractor.build_extraction_prompt("https://example.com")

  # Include in ScrapFly API request
  Client.scrape_google("keyword", extraction_prompt: prompt)

  # Parse response
  LLMExtractor.parse_llm_response(response, "https://example.com")
  ```
  """

  require Logger

  @serp_features [
    "featured_snippet",
    "people_also_ask",
    "local_pack",
    "video_carousel",
    "image_pack",
    "shopping_results",
    "knowledge_panel"
  ]

  @prompt_template """
  Extract the following information from these Google search results in JSON format:

  1. The position (1-100) where the URL '%{target_url}' appears in organic results
  2. The top 10 competing URLs with their positions and titles
  3. Any SERP features present: #{Enum.join(@serp_features, ", ")}

  Return STRICTLY VALID JSON in this format:
  {
    "position": 3,
    "competitors": [
      {"position": 1, "url": "https://example.com", "title": "Page Title"}
    ],
    "serp_features": ["featured_snippet"]
  }

  IMPORTANT:
  - If target URL not found, return "position": null
  - Only include organic results (exclude ads)
  - Ensure all JSON is valid (proper quotes, commas)
  """

  def build_extraction_prompt(target_url) do
    @prompt_template
    |> String.replace("%{target_url}", target_url)
    |> String.trim()
  end

  def parse_llm_response(scrapfly_response, target_url) do
    start_time = System.monotonic_time(:millisecond)

    result = extract_data(scrapfly_response)

    duration_ms = System.monotonic_time(:millisecond) - start_time
    emit_telemetry(result, duration_ms, target_url)

    result
  end

  defp extract_data(response) do
    case get_in(response, ["result", "extracted_data", "data"]) do
      nil ->
        Logger.warning("LLM extraction returned no data")
        build_empty_result("No extracted data from LLM")

      data when is_map(data) ->
        %{
          position: data["position"],
          competitors: normalize_competitors(data["competitors"] || []),
          serp_features: data["serp_features"] || [],
          parsed_at: DateTime.utc_now()
        }

      _ ->
        Logger.error("LLM extraction returned invalid format")
        build_empty_result("Invalid LLM response format")
    end
  end

  defp normalize_competitors(competitors) when is_list(competitors) do
    Enum.take(competitors, 10)
    |> Enum.map(fn comp ->
      %{
        position: comp["position"],
        url: comp["url"],
        title: comp["title"]
      }
    end)
  end

  defp normalize_competitors(_), do: []

  defp build_empty_result(error_message) do
    %{
      position: nil,
      competitors: [],
      serp_features: [],
      parsed_at: DateTime.utc_now(),
      error: error_message
    }
  end

  defp emit_telemetry(result, duration_ms, target_url) do
    metadata = %{
      target_url: target_url,
      position_found: !is_nil(result.position),
      competitors_count: length(result.competitors),
      features_count: length(result.serp_features)
    }

    :telemetry.execute(
      [:gsc_analytics, :serp, :llm_extraction],
      %{duration: duration_ms},
      metadata
    )
  end
end
```

**Run tests again:**
```bash
mix test test/gsc_analytics/data_sources/serp/core/llm_extractor_test.exs
# Expected: All tests still pass
```

## Integration with Client (T005)

Update T005 to include `extraction_prompt`:

```elixir
# In Client.scrape_google/2
def scrape_google(keyword, opts \\ []) do
  geo = opts[:geo] || Config.default_geo()
  target_url = opts[:target_url] || ""  # NEW: Pass target URL

  search_url = build_search_url(keyword, geo)

  # NEW: Include extraction_prompt for LLM extraction
  extraction_prompt = LLMExtractor.build_extraction_prompt(target_url)

  params = %{
    "key" => Config.api_key(),
    "url" => search_url,
    "country" => geo,
    "render_js" => "true",
    "asp" => "true",
    "extraction_prompt" => extraction_prompt  # NEW: LLM extraction
  }

  execute_request("#{Config.base_url()}/scrape", params)
end
```

## Definition of Done
- [x] RED → GREEN → REFACTOR completed
- [ ] LLM extraction prompt generates correct instructions
- [ ] Parses ScrapFly LLM response accurately
- [ ] Handles missing URLs gracefully
- [ ] Telemetry emitted
- [ ] Tests pass

## Cost Comparison

| Approach | API Credits | Complexity | Resilience |
|----------|------------|------------|------------|
| **Custom JSON Parser** | 31 (base) | High | Low (breaks on format change) |
| **LLM Extraction** | 36 (31+5) | Low | High (adapts to changes) |

**Recommendation:** Use LLM extraction for 5 extra credits, get resilient parsing.

## 📚 Reference Documentation
- **TDD Guide:** [Complete Guide](/Users/flor/Developer/prism/docs/elixir-tdd-research.md)
- **ScrapFly LLM Extraction:** [Official Docs](https://scrapfly.io/docs/scrape-api/extraction)
- **Local ScrapFly Docs:** [scrapfly-llm.md](/Users/flor/Developer/prism/docs/scrapfly-llm.md)
- **Pricing:** https://scrapfly.io/docs/scrape-api/extraction#pricing

## Notes
- **Changed from custom JSON parser to LLM extraction** (simpler, more resilient)
- Cost increase: 5 credits (worth it for auto-adapting parser)
- Natural language prompts are maintainable
- Handles Google SERP format changes automatically
