#!/usr/bin/env elixir

# Script to test SERP HTML parsing with actual ScrapFly response
# Usage: elixir test_serp_html.exs

Mix.install([
  {:ecto, "~> 3.10"}
])

defmodule TestHTMLParser do
  @moduledoc """
  Test the HTML parser with the actual response from ScrapFly
  """

  def run do
    # Get the latest SERP snapshot from the database
    IO.puts("\n=== Testing SERP HTML Parser ===\n")

    # You'll need to run this in IEx with access to your Repo
    # For now, let's just test the parser logic directly

    # Sample HTML structure that Google uses
    sample_html = """
    <html>
      <body>
        <div id="search">
          <div class="g">
            <div class="yuRUbf">
              <a href="https://example.com/page1">
                <h3>Example Page 1</h3>
              </a>
            </div>
          </div>
          <div class="g">
            <div class="yuRUbf">
              <a href="/url?q=https://scrapfly.io/blog/posts/how-to-scrape-instagram&amp;sa=U">
                <h3>How to Scrape Instagram</h3>
              </a>
            </div>
          </div>
          <div class="g">
            <div class="yuRUbf">
              <a href="https://another-site.com">
                <h3>Another Page</h3>
              </a>
            </div>
          </div>
        </div>
      </body>
    </html>
    """

    IO.puts("Sample HTML length: #{String.length(sample_html)}")
    IO.puts("\nExtracting URLs...")

    # Test URL extraction
    urls = extract_urls_from_html(sample_html)
    IO.puts("Found #{length(urls)} URLs:")
    Enum.each(urls, fn url -> IO.puts("  - #{url}") end)

    IO.puts("\nFiltering organic results...")
    organic = filter_organic_results(urls)
    IO.puts("Found #{length(organic)} organic results:")
    Enum.each(organic, fn url -> IO.puts("  - #{url}") end)

    IO.puts("\nSearching for target URL: scrapfly.io/blog")
    target = "scrapfly.io/blog"
    position = find_position(organic, target)

    case position do
      nil -> IO.puts("❌ Target URL not found in results")
      pos -> IO.puts("✅ Found at position #{pos}")
    end
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

  defp decode_google_redirect_url(url) do
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

  defp normalize_url(url) do
    url
    |> String.replace(~r{^https?://}, "")
    |> String.replace(~r{/$}, "")
    |> String.downcase()
  end

  defp find_position(urls, normalized_target) do
    urls
    |> Enum.with_index(1)
    |> Enum.find_value(fn {url, index} ->
      if String.contains?(normalize_url(url), normalized_target) do
        index
      end
    end)
  end
end

TestHTMLParser.run()
