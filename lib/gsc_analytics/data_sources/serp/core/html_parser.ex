defmodule GscAnalytics.DataSources.SERP.Core.HTMLParser do
  @moduledoc """
  Parses markdown/HTML content from Google SERP to extract ranking positions.

  ScrapFly returns content in markdown format which contains clean links to
  organic search results. This parser extracts URLs from markdown link syntax
  and finds the position of the target URL.

  ## Examples

      iex> response = %{"result" => %{"content" => "markdown content..."}}
      iex> HTMLParser.parse_serp_response(response, "https://example.com")
      %{
        position: 3,
        competitors: [...],
        serp_features: [],
        parsed_at: ~U[2025-10-04 15:30:00Z]
      }

  """

  require Logger

  @doc """
  Parse ScrapFly response (without LLM extraction) to find target URL position.

  ## Parameters

  - `scrapfly_response`: Map with `%{"result" => %{"content" => "<html>..."}}`
  - `target_url`: The URL to find in search results (e.g., "https://example.com")

  ## Returns

  Map with:
  - `:position` - Integer position (1-100) or `nil` if not found
  - `:competitors` - List of competing URLs (currently empty, can be enhanced)
  - `:serp_features` - List of detected SERP features (currently empty)
  - `:parsed_at` - UTC timestamp of parsing
  - `:error` - String error message (only present on failure)

  """
  def parse_serp_response(scrapfly_response, target_url) do
    html_content = get_in(scrapfly_response, ["result", "content"])

    case html_content do
      nil ->
        %{
          position: nil,
          competitors: [],
          serp_features: [],
          parsed_at: DateTime.utc_now(),
          error: "No HTML content in ScrapFly response"
        }

      html when is_binary(html) ->
        position = find_url_position(html, normalize_url(target_url))
        serp_features = detect_serp_features(html)
        ai_overview = GscAnalytics.DataSources.SERP.Core.AIOverviewExtractor.extract(html)

        %{
          position: position,
          competitors: [],
          serp_features: serp_features,
          ai_overview_present: ai_overview.present,
          ai_overview_text: ai_overview.text,
          ai_overview_citations: ai_overview.citations,
          parsed_at: DateTime.utc_now()
        }
    end
  end

  # Private Functions

  @doc false
  def normalize_url(url) do
    # Remove protocol and trailing slash for fuzzy matching
    url
    |> String.replace(~r{^https?://}, "")
    |> String.replace(~r{/$}, "")
    |> String.downcase()
  end

  @doc false
  def find_url_position(html, normalized_target) do
    # Extract organic search result links
    # Google uses <div class="..."> with nested <a> tags
    # Pattern: <a href="/url?q=ACTUAL_URL&..." or <a href="ACTUAL_URL"...>

    case extract_organic_results(html) do
      [] ->
        Logger.debug("No organic results found in HTML",
          html_length: String.length(html),
          target: normalized_target
        )

        nil

      urls ->
        urls
        |> Enum.with_index(1)
        |> Enum.find_value(fn {url, index} ->
          if String.contains?(normalize_url(url), normalized_target) do
            index
          end
        end)
    end
  end

  @doc false
  def extract_organic_results(content) do
    # Google SERP structure (as of 2025):
    # Organic results are contained in <div class="yuRUbf"> elements
    # Each yuRUbf contains the title link <a href="...">
    # This is more reliable than extracting all links and filtering

    # Try extracting from yuRUbf containers first (most reliable)
    yuRUbf_urls = extract_from_yuRUbf_containers(content)

    if length(yuRUbf_urls) > 0 do
      yuRUbf_urls
    else
      # Fallback to generic extraction for non-Google HTML or old formats
      content
      |> extract_urls_from_content()
      |> filter_organic_results()
      |> Enum.take(100)
    end
  end

  defp extract_from_yuRUbf_containers(html) do
    # Pattern: <div class="yuRUbf"> ... <a href="URL"> ... </a> ... </div>
    # This is Google's container for organic result titles
    ~r/<div[^>]*class="[^"]*yuRUbf[^"]*"[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>/is
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [url] ->
      # Decode HTML entities
      url
      |> String.replace("&amp;", "&")
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
    end)
    |> Enum.reject(fn url ->
      # Filter out Google internal links that might slip through
      String.contains?(url, "google.com/") or
        String.starts_with?(url, "/")
    end)
    |> Enum.uniq()
  end

  defp extract_urls_from_content(content) do
    # Try markdown links first: [text](url)
    markdown_urls = extract_markdown_links(content)

    # Only use markdown if we found actual HTTP(S) URLs
    # This filters out JavaScript patterns like [init](id) or [d](b)
    has_real_urls =
      Enum.any?(markdown_urls, fn url ->
        String.starts_with?(url, "http://") or String.starts_with?(url, "https://")
      end)

    if has_real_urls do
      markdown_urls
    else
      # Fallback to HTML href extraction
      extract_urls_from_html(content)
    end
  end

  defp extract_markdown_links(content) do
    # Match markdown link syntax: [text](url)
    ~r/\[([^\]]+)\]\(([^)]+)\)/
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [_text, url] -> url end)
  end

  defp extract_urls_from_html(html) do
    # Match href="..." or href='/...' attributes
    ~r/href=["']([^"']+)["']/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [url] -> url end)
  end

  defp filter_organic_results(urls) do
    urls
    |> Enum.filter(&is_organic_result?/1)
    |> Enum.map(&decode_google_redirect_url/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp is_organic_result?(url) do
    # Exclude Google internal links, ads, and navigation
    not (String.starts_with?(url, "#") or
           String.starts_with?(url, "/search") or
           String.starts_with?(url, "/preferences") or
           String.starts_with?(url, "/advanced_search") or
           String.contains?(url, "google.com/") or
           String.contains?(url, "googleusercontent.com") or
           String.contains?(url, "googleadservices.com")) and
      (String.starts_with?(url, "http://") or
         String.starts_with?(url, "https://") or
         String.starts_with?(url, "/url?q="))
  end

  defp decode_google_redirect_url(url) do
    # Google often wraps URLs like: /url?q=https://example.com&sa=...
    case String.starts_with?(url, "/url?q=") do
      true ->
        url
        |> URI.decode()
        |> String.replace(~r{^/url\?q=}, "")
        |> String.split("&")
        |> List.first()

      false ->
        url
    end
  end

  @doc false
  def detect_serp_features(html) do
    features = []

    # Check for AI Overview
    features =
      if has_ai_overview?(html) do
        ["ai_overview" | features]
      else
        features
      end

    # Check for People Also Ask
    features =
      if has_people_also_ask?(html) do
        ["people_also_ask" | features]
      else
        features
      end

    # Check for Featured Snippet
    features =
      if has_featured_snippet?(html) do
        ["featured_snippet" | features]
      else
        features
      end

    # Check for Video results
    features =
      if has_video_results?(html) do
        ["videos" | features]
      else
        features
      end

    # Check for Image pack
    features =
      if has_image_pack?(html) do
        ["images" | features]
      else
        features
      end

    Enum.reverse(features)
  end

  defp has_ai_overview?(html) do
    # AI Overview appears as <h1>AI Overview</h1> or similar
    String.contains?(html, ">AI Overview<") or
      String.contains?(html, "data-kpid=\"sge_") or
      Regex.match?(~r/<h[1-3][^>]*>AI Overview<\/h[1-3]>/i, html)
  end

  defp has_people_also_ask?(html) do
    # People Also Ask section
    String.contains?(html, "People also ask") or
      String.contains?(html, "related-question")
  end

  defp has_featured_snippet?(html) do
    # Featured snippets have specific data attributes
    String.contains?(html, "data-attrid=\"FeaturedSnippet\"") or
      Regex.match?(~r/class="[^"]*kp-header[^"]*"/i, html)
  end

  defp has_video_results?(html) do
    # Video carousels or video results
    String.contains?(html, "video-voyager") or
      String.contains?(html, "video_result") or
      Regex.match?(~r/data-hveid="[^"]*video/i, html)
  end

  defp has_image_pack?(html) do
    # Image pack carousel
    String.contains?(html, "image_result") or
      String.contains?(html, "islir")
  end
end
