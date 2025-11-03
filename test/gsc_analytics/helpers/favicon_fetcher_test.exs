defmodule GscAnalytics.Helpers.FaviconFetcherTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.Helpers.FaviconFetcher

  describe "get_favicon_url/2" do
    test "returns favicon URL for domain property" do
      assert FaviconFetcher.get_favicon_url("sc-domain:example.com") ==
               "https://www.google.com/s2/favicons?domain=example.com&sz=32"
    end

    test "returns favicon URL for URL-prefix property with https" do
      assert FaviconFetcher.get_favicon_url("https://example.com/") ==
               "https://www.google.com/s2/favicons?domain=example.com&sz=32"
    end

    test "returns favicon URL for URL-prefix property with http" do
      assert FaviconFetcher.get_favicon_url("http://example.com/") ==
               "https://www.google.com/s2/favicons?domain=example.com&sz=32"
    end

    test "returns favicon URL for URL-prefix property with subdomain" do
      assert FaviconFetcher.get_favicon_url("https://www.example.com/") ==
               "https://www.google.com/s2/favicons?domain=www.example.com&sz=32"
    end

    test "returns favicon URL for URL-prefix property with path" do
      assert FaviconFetcher.get_favicon_url("https://example.com/blog/") ==
               "https://www.google.com/s2/favicons?domain=example.com&sz=32"
    end

    test "respects custom size option" do
      assert FaviconFetcher.get_favicon_url("sc-domain:example.com", size: 64) ==
               "https://www.google.com/s2/favicons?domain=example.com&sz=64"
    end

    test "URL-encodes domain names with special characters" do
      assert FaviconFetcher.get_favicon_url("sc-domain:例え.jp") ==
               "https://www.google.com/s2/favicons?domain=%E4%BE%8B%E3%81%88.jp&sz=32"
    end

    test "returns nil for nil input" do
      assert FaviconFetcher.get_favicon_url(nil) == nil
    end

    test "returns nil for empty string" do
      assert FaviconFetcher.get_favicon_url("") == nil
    end

    test "returns nil for invalid property URL" do
      assert FaviconFetcher.get_favicon_url("invalid") == nil
    end

    test "returns nil for malformed URL" do
      assert FaviconFetcher.get_favicon_url("https://") == nil
    end
  end

  describe "extract_domain/1" do
    test "extracts domain from sc-domain: prefix" do
      assert FaviconFetcher.extract_domain("sc-domain:example.com") == "example.com"
    end

    test "extracts domain from sc-domain: with subdomain" do
      assert FaviconFetcher.extract_domain("sc-domain:www.example.com") == "www.example.com"
    end

    test "extracts domain from https URL" do
      assert FaviconFetcher.extract_domain("https://example.com/") == "example.com"
    end

    test "extracts domain from http URL" do
      assert FaviconFetcher.extract_domain("http://example.com/") == "example.com"
    end

    test "extracts domain from URL with path" do
      assert FaviconFetcher.extract_domain("https://example.com/blog/post") == "example.com"
    end

    test "extracts domain from URL with subdomain" do
      assert FaviconFetcher.extract_domain("https://www.example.com/") == "www.example.com"
    end

    test "extracts domain from URL with port" do
      assert FaviconFetcher.extract_domain("https://example.com:8080/") == "example.com"
    end

    test "handles sc-domain: with trailing whitespace" do
      assert FaviconFetcher.extract_domain("sc-domain:example.com ") == "example.com"
    end

    test "returns nil for empty sc-domain:" do
      assert FaviconFetcher.extract_domain("sc-domain:") == nil
    end

    test "returns nil for URL without host" do
      assert FaviconFetcher.extract_domain("https://") == nil
    end

    test "returns nil for invalid format" do
      assert FaviconFetcher.extract_domain("invalid") == nil
    end

    test "returns nil for nil input" do
      assert FaviconFetcher.extract_domain(nil) == nil
    end

    test "returns nil for non-string input" do
      assert FaviconFetcher.extract_domain(123) == nil
    end
  end
end
