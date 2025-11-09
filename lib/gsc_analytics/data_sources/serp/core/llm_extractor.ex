defmodule GscAnalytics.DataSources.SERP.Core.LLMExtractor do
  @moduledoc """
  Extract SERP position using ScrapFly's LLM Extraction API.

  This approach uses natural language instructions instead of custom parsers,
  making it resilient to Google SERP format changes.

  ## Cost
  - 5 API credits per query (LLM prompt pricing)
  - Combined with base SERP scrape (31 credits) = 36 total credits

  ## Example Usage
  ```elixir
  # Build extraction prompt
  prompt = LLMExtractor.build_extraction_prompt("https://example.com")

  # Pass to ScrapFly API via Client
  {:ok, response} = Client.scrape_google("test query",
    target_url: "https://example.com",
    extraction_prompt: prompt
  )

  # Parse LLM response
  parsed = LLMExtractor.parse_llm_response(response, "https://example.com")
  # => %{position: 3, competitors: [...], serp_features: [...]}
  ```
  """

  @doc """
  Build natural language prompt for SERP extraction.

  The prompt instructs the LLM to extract:
  1. Position (1-100) where target URL appears in organic results
  2. Top 10 competing URLs with their positions and titles
  3. SERP features present (featured_snippet, people_also_ask, etc.)

  Returns strictly valid JSON for easy parsing.

  ## Parameters
  - `target_url` - The URL to track in SERP results

  ## Example
      iex> LLMExtractor.build_extraction_prompt("https://example.com")
      "Extract the following information..."
  """
  def build_extraction_prompt(target_url) do
    """
    Extract the following information from these Google search results in JSON format:

    1. The position (1-100) where the URL '#{target_url}' appears in organic results
    2. The top 10 competing URLs with their positions and titles
    3. Any SERP features present: featured_snippet, people_also_ask, local_pack, video_carousel, image_pack, shopping_results, knowledge_panel

    Return STRICTLY VALID JSON in this format:
    {
      "position": 3,
      "competitors": [
        {"position": 1, "url": "https://competitor.com", "title": "Page Title"}
      ],
      "serp_features": ["featured_snippet", "people_also_ask"]
    }

    IMPORTANT:
    - If target URL not found in results, return "position": null
    - Only include organic results (exclude ads and sponsored content)
    - Ensure all JSON is valid (proper quotes, no trailing commas)
    - competitors array should contain up to 10 entries
    """
  end

  @doc """
  Parse LLM extraction response from ScrapFly API.

  Extracts the nested `result.extracted_data.data` path from the ScrapFly
  response structure and parses the LLM-generated JSON.

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

  ## Parameters
  - `scrapfly_response` - Full ScrapFly API response map
  - `target_url` - The URL being tracked (currently unused, for future logging)

  ## Returns
  Map with:
  - `:position` - Integer (1-100) or nil if not found
  - `:competitors` - List of competitor maps with position/url/title
  - `:serp_features` - List of SERP feature strings
  - `:parsed_at` - DateTime of parsing
  - `:error` - String error message (only present on errors)

  ## Examples
      iex> parse_llm_response(valid_response, "https://example.com")
      %{
        position: 3,
        competitors: [%{"position" => 1, "url" => "...", "title" => "..."}],
        serp_features: ["featured_snippet"],
        parsed_at: ~U[2025-01-09 12:00:00Z]
      }

      iex> parse_llm_response(not_found_response, "https://example.com")
      %{position: nil, competitors: [], serp_features: [], parsed_at: ~U[...]}
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
        # Successfully extracted LLM response
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
