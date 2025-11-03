defmodule GscAnalytics.Helpers.FaviconFetcher do
  @moduledoc """
  Helper module for fetching and generating favicon URLs for Google Search Console properties.

  This module provides utilities to extract domain names from GSC property URLs and generate
  favicon URLs using Google's favicon service. Supports both domain properties (sc-domain:)
  and URL-prefix properties (https://).

  ## Examples

      iex> FaviconFetcher.get_favicon_url("sc-domain:example.com")
      "https://www.google.com/s2/favicons?domain=example.com&sz=32"

      iex> FaviconFetcher.get_favicon_url("https://example.com/")
      "https://www.google.com/s2/favicons?domain=example.com&sz=32"

      iex> FaviconFetcher.get_favicon_url("https://www.example.com/blog")
      "https://www.google.com/s2/favicons?domain=www.example.com&sz=32"
  """

  @doc """
  Generates a favicon URL for a given GSC property URL.

  Accepts both GSC domain properties (prefixed with "sc-domain:") and URL-prefix properties.
  Uses Google's favicon service which provides reliable favicon fetching with fallbacks.

  ## Parameters

    * `property_url` - The Google Search Console property URL (e.g., "sc-domain:example.com")
    * `opts` - Optional keyword list with the following options:
      * `:size` - Favicon size in pixels (default: 32, options: 16, 32, 64, 128, 256)

  ## Returns

  Returns a string URL to the favicon, or `nil` if the property URL is invalid.

  ## Examples

      iex> get_favicon_url("sc-domain:scrapfly.io")
      "https://www.google.com/s2/favicons?domain=scrapfly.io&sz=32"

      iex> get_favicon_url("https://scrapfly.io/", size: 64)
      "https://www.google.com/s2/favicons?domain=scrapfly.io&sz=64"

      iex> get_favicon_url(nil)
      nil
  """
  @spec get_favicon_url(String.t() | nil, keyword()) :: String.t() | nil
  def get_favicon_url(property_url, opts \\ [])
  def get_favicon_url(nil, _opts), do: nil
  def get_favicon_url("", _opts), do: nil

  def get_favicon_url(property_url, opts) when is_binary(property_url) do
    size = Keyword.get(opts, :size, 32)

    case extract_domain(property_url) do
      nil -> nil
      domain -> "https://www.google.com/s2/favicons?domain=#{URI.encode(domain)}&sz=#{size}"
    end
  end

  @doc """
  Extracts the domain name from a GSC property URL.

  Handles both domain properties (sc-domain:example.com) and URL-prefix properties
  (https://example.com/path).

  ## Examples

      iex> extract_domain("sc-domain:example.com")
      "example.com"

      iex> extract_domain("https://example.com/")
      "example.com"

      iex> extract_domain("https://www.example.com/blog")
      "www.example.com"

      iex> extract_domain("invalid")
      nil
  """
  @spec extract_domain(String.t()) :: String.t() | nil
  def extract_domain(property_url) when is_binary(property_url) do
    cond do
      # Handle sc-domain: prefix (domain properties)
      String.starts_with?(property_url, "sc-domain:") ->
        property_url
        |> String.replace_prefix("sc-domain:", "")
        |> String.trim()
        |> case do
          "" -> nil
          domain -> domain
        end

      # Handle URL-prefix properties (https://, http://)
      String.starts_with?(property_url, "http://") or
          String.starts_with?(property_url, "https://") ->
        case URI.parse(property_url) do
          %URI{host: host} when is_binary(host) and host != "" -> host
          _ -> nil
        end

      # Unknown format
      true ->
        nil
    end
  end

  def extract_domain(_), do: nil
end
