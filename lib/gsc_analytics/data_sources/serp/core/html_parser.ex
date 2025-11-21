defmodule GscAnalytics.DataSources.SERP.Core.HTMLParser do
  @moduledoc """
  Parses ScrapFly SERP HTML to extract ranking positions, competitors, and
  content-type metadata for downstream analytics.

  Google frequently tweaks markup, so this parser combines CSS selectors and
  regex fallbacks to stay resilient.
  """

  alias GscAnalytics.DataSources.SERP.Core.AIOverviewExtractor

  require Logger
  alias Floki

  @forum_domains [
    "stackexchange.com",
    "stackoverflow.com",
    "stackovernet.com",
    "serverfault.com",
    "superuser.com",
    "quora.com"
  ]
  @default_content_type "website"

  @doc """
  Parse ScrapFly response (without LLM extraction) to find target URL position
  and capture the top competitors.
  """
  def parse_serp_response(scrapfly_response, target_url) do
    html_content = get_in(scrapfly_response, ["result", "content"])

    case html_content do
      nil ->
        %{
          position: nil,
          competitors: [],
          serp_features: [],
          ai_overview_present: false,
          ai_overview_text: nil,
          ai_overview_citations: [],
          content_types_present: [],
          parsed_at: DateTime.utc_now(),
          error: "No HTML content in ScrapFly response"
        }

      html when is_binary(html) ->
        normalized_target = normalize_url(target_url)
        competitors = extract_competitors(html)

        position =
          position_from_competitors(competitors, normalized_target) ||
            find_url_position(html, normalized_target)

        serp_features = detect_serp_features(html)
        ai_overview = AIOverviewExtractor.extract(html)

        %{
          position: position,
          competitors: competitors,
          serp_features: serp_features,
          ai_overview_present: ai_overview.present,
          ai_overview_text: ai_overview.text,
          ai_overview_citations: ai_overview.citations,
          content_types_present: content_types_from_competitors(competitors),
          parsed_at: DateTime.utc_now()
        }
    end
  end

  # Private Functions

  @doc false
  def normalize_url(url) do
    url
    |> to_string()
    |> String.replace(~r{^https?://}, "")
    |> String.replace(~r{/$}, "")
    |> String.downcase()
  end

  defp position_from_competitors([], _normalized_target), do: nil

  defp position_from_competitors(competitors, normalized_target) do
    competitors
    |> Enum.find(fn competitor ->
      case Map.get(competitor, :url) do
        nil -> false
        url -> String.contains?(normalize_url(url), normalized_target)
      end
    end)
    |> case do
      %{position: position} -> position
      _ -> nil
    end
  end

  @doc false
  def find_url_position(html, normalized_target) do
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
    yuRUbf_urls = extract_from_yuRUbf_containers(content)

    if length(yuRUbf_urls) > 0 do
      yuRUbf_urls
    else
      content
      |> extract_urls_from_content()
      |> filter_organic_results()
      |> Enum.take(100)
    end
  end

  defp extract_from_yuRUbf_containers(html) do
    ~r/<div[^>]*class="[^"]*yuRUbf[^"]*"[^>]*>.*?<a[^>]*href="([^"]+)"[^>]*>/is
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [url] ->
      url
      |> String.replace("&amp;", "&")
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
    end)
    |> Enum.reject(fn url ->
      String.contains?(url, "google.com/") or String.starts_with?(url, "/")
    end)
    |> Enum.uniq()
  end

  defp extract_urls_from_content(content) do
    markdown_urls = extract_markdown_links(content)

    has_real_urls =
      Enum.any?(markdown_urls, fn url ->
        String.starts_with?(url, "http://") or String.starts_with?(url, "https://")
      end)

    if has_real_urls do
      markdown_urls
    else
      extract_urls_from_html(content)
    end
  end

  defp extract_markdown_links(content) do
    ~r/\[([^\]]+)\]\(([^)]+)\)/
    |> Regex.scan(content, capture: :all_but_first)
    |> Enum.map(fn [_text, url] -> url end)
  end

  defp extract_urls_from_html(html) do
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

  defp decode_google_redirect_url(url) when is_binary(url) do
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

  defp decode_google_redirect_url(_), do: nil

  @doc """
  Extracts the normalized domain (without protocol or leading www) from a URL.
  """
  @spec extract_domain(String.t() | nil) :: String.t()
  def extract_domain(url) when is_binary(url) do
    url
    |> URI.parse()
    |> case do
      %URI{host: host} when is_binary(host) ->
        host
        |> String.downcase()
        |> String.replace(~r/^www\./, "")

      _ ->
        ""
    end
  end

  def extract_domain(_), do: ""

  @doc """
  Classifies a SERP result by content type.
  """
  @spec classify_content_type(String.t() | nil, String.t() | nil) :: String.t()
  def classify_content_type(url, title) do
    domain = extract_domain(url)
    lower_domain = String.downcase(domain || "")
    lower_title = String.downcase(title || "")

    cond do
      lower_domain == "" and lower_title == "" ->
        @default_content_type

      String.contains?(lower_domain, "reddit.com") ->
        "reddit"

      String.contains?(lower_domain, "youtube.com") or String.contains?(lower_domain, "youtu.be") ->
        "youtube"

      forum_domain?(lower_domain) ->
        "forum"

      String.contains?(lower_title, "people also ask") ->
        "paa"

      true ->
        @default_content_type
    end
  end

  @doc """
  Extracts top 10 competitors from SERP HTML.
  """
  @spec extract_competitors(String.t()) :: [map()]
  def extract_competitors(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        document
        |> Floki.find("div.yuRUbf")
        |> Enum.take(10)
        |> Enum.with_index(1)
        |> Enum.map(&build_competitor_map/1)
        |> Enum.reject(&is_nil/1)

      {:error, reason} ->
        Logger.debug("Failed to parse SERP HTML", reason: inspect(reason))
        []
    end
  end

  def extract_competitors(_), do: []

  defp build_competitor_map({element, position}) do
    url =
      element
      |> Floki.find("a")
      |> Floki.attribute("href")
      |> List.first()
      |> decode_google_redirect_url()

    cond do
      is_nil(url) or url == "" ->
        nil

      true ->
        title =
          element
          |> Floki.find("h3")
          |> Floki.text()
          |> normalize_whitespace()

        %{
          position: position,
          url: url,
          title: title,
          domain: extract_domain(url),
          content_type: classify_content_type(url, title)
        }
    end
  end

  defp forum_domain?(domain) when is_binary(domain) do
    Enum.any?(@forum_domains, &String.contains?(domain, &1))
  end

  defp forum_domain?(_), do: false

  defp content_types_from_competitors(competitors) do
    competitors
    |> Enum.map(& &1.content_type)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_whitespace(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_whitespace(_), do: ""

  @doc false
  def detect_serp_features(html) do
    features = []

    features =
      if has_ai_overview?(html) do
        ["ai_overview" | features]
      else
        features
      end

    features =
      if has_people_also_ask?(html) do
        ["people_also_ask" | features]
      else
        features
      end

    features =
      if has_featured_snippet?(html) do
        ["featured_snippet" | features]
      else
        features
      end

    features =
      if has_video_results?(html) do
        ["videos" | features]
      else
        features
      end

    features =
      if has_image_pack?(html) do
        ["images" | features]
      else
        features
      end

    Enum.reverse(features)
  end

  defp has_ai_overview?(html) do
    String.contains?(html, ">AI Overview<") or
      String.contains?(html, "data-kpid=\"sge_") or
      Regex.match?(~r/<h[1-3][^>]*>AI Overview<\/h[1-3]>/i, html)
  end

  defp has_people_also_ask?(html) do
    String.contains?(html, "People also ask") or
      String.contains?(html, "related-question")
  end

  defp has_featured_snippet?(html) do
    String.contains?(html, "data-attrid=\"FeaturedSnippet\"") or
      Regex.match?(~r/class="[^"]*kp-header[^"]*"/i, html)
  end

  defp has_video_results?(html) do
    String.contains?(html, "video-voyager") or
      String.contains?(html, "video_result") or
      Regex.match?(~r/data-hveid="[^"]*video/i, html)
  end

  defp has_image_pack?(html) do
    String.contains?(html, "image_result") or
      String.contains?(html, "islir")
  end
end
