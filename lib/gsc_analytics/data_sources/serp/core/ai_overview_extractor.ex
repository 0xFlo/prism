defmodule GscAnalytics.DataSources.SERP.Core.AIOverviewExtractor do
  @moduledoc """
  Extracts AI Overview content and citations from Google SERP HTML.

  Uses multiple fallback patterns for robustness against Google's frequent UI changes.
  """

  @doc """
  Extract AI Overview data from SERP HTML.

  Returns a map with:
  - `present`: boolean - whether AI Overview exists
  - `text`: string - the AI-generated content (first 1000 chars)
  - `citations`: list of maps - [{url, domain, position}]
  """
  def extract(html) when is_binary(html) do
    case find_ai_overview_section(html) do
      nil ->
        %{present: false, text: nil, citations: []}

      ai_section ->
        %{
          present: true,
          text: extract_text(ai_section),
          citations: extract_citations(ai_section)
        }
    end
  end

  def extract(_), do: %{present: false, text: nil, citations: []}

  # Private Functions

  defp find_ai_overview_section(html) do
    # Try multiple patterns in order of reliability
    patterns = [
      # Pattern 1: Standard H1 header (most common as of 2025)
      ~r/<h1[^>]*>AI Overview<\/h1>(.*?)(?:<h1[^>]*>|<div[^>]*class="[^"]*kb0PBd)/is,

      # Pattern 2: H2/H3 variations
      ~r/<h[23][^>]*>AI Overview<\/h[23]>(.*?)(?:<h[123][^>]*>|<div[^>]*class="[^"]*kb0PBd)/is,

      # Pattern 3: data-kpid SGE attribute
      ~r/<div[^>]*data-kpid="sge_[^"]*"[^>]*>(.*?)(?:<div[^>]*class="[^"]*kb0PBd|<h1)/is,

      # Pattern 4: Broader AI/SGE section
      ~r/<div[^>]*(?:class="[^"]*ai-overview|data-attrid="[^"]*ai[^"]*")[^>]*>(.*?)(?:<div[^>]*class="[^"]*kb0PBd)/is
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, html, capture: :all_but_first) do
        [content] -> content
        nil -> nil
      end
    end)
  end

  defp extract_text(ai_section) do
    ai_section
    # Remove script and style tags
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    # Remove HTML tags
    |> String.replace(~r/<[^>]+>/, " ")
    # Decode common HTML entities
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    # Limit to first 1000 chars for database storage
    |> String.slice(0..999)
  end

  defp extract_citations(ai_section) do
    # Extract all links from AI Overview section
    ~r/<a[^>]*href="([^"]+)"[^>]*>([^<]*)<\/a>/i
    |> Regex.scan(ai_section, capture: :all_but_first)
    |> Enum.map(fn [url, text] -> {url, text} end)
    # Filter to external links only (citations)
    |> Enum.filter(&is_citation?/1)
    |> Enum.map(&decode_citation/1)
    |> Enum.with_index(1)
    |> Enum.map(fn {{url, domain}, position} ->
      %{
        url: url,
        domain: domain,
        position: position
      }
    end)
    # Limit to 20 citations max
    |> Enum.take(20)
  end

  defp is_citation?({url, _text}) do
    # Include if it's an external HTTP link or Google redirect
    # Exclude Google's own domains
    (String.starts_with?(url, "http://") or String.starts_with?(url, "https://") or
       String.starts_with?(url, "/url?q=http")) and
      not String.contains?(url, "google.com") and
      not String.contains?(url, "googleusercontent.com") and
      not String.contains?(url, "googleadservices.com") and
      not String.contains?(url, "gstatic.com")
  end

  defp decode_citation({url, _text}) do
    # Decode Google redirect URLs: /url?q=https://example.com&...
    clean_url =
      if String.starts_with?(url, "/url?q=") do
        url
        |> URI.decode()
        |> String.replace(~r{^/url\?q=}, "")
        |> String.split("&")
        |> List.first()
      else
        url
      end

    # Extract domain
    domain =
      case URI.parse(clean_url) do
        %URI{host: host} when is_binary(host) -> host
        _ -> "unknown"
      end

    {clean_url, domain}
  end
end
