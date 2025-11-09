defmodule GscAnalytics.DataSources.SERP.Core.HTMLParser do
  @moduledoc """
  Parses raw HTML from Google SERP to extract ranking positions.

  Uses pattern matching and simple string operations to find URL positions
  in organic search results. More brittle than LLM extraction but gives
  full control over parsing logic.

  ## Examples

      iex> response = %{"result" => %{"content" => "<html>...</html>"}}
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

        %{
          position: position,
          competitors: [],
          serp_features: [],
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
        Logger.warning("No organic results found in HTML",
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
  def extract_organic_results(html) do
    # Google SERP structure (as of 2025):
    # Organic results typically have <a> tags with href attributes
    # Pattern 1: <a href="/url?q=https://example.com&...">
    # Pattern 2: <a href="https://example.com" ...>

    # This regex finds all <a> tags within organic result divs
    # We look for href attributes and extract the URLs

    html
    |> extract_urls_from_html()
    |> filter_organic_results()
    # Google shows max 100 results per page
    |> Enum.take(100)
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
end
