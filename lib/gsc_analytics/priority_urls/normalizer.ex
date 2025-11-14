defmodule GscAnalytics.PriorityUrls.Normalizer do
  @moduledoc """
  Normalizes URLs for deterministic deduplication.

  Applied rules:
  * Lowercase scheme and hostname
  * Ensure root path (`/`) exists
  * Trim trailing slashes for non-root paths
  * Preserve query parameters, fragments, ports, and path case
  """

  @spec normalize_url(String.t()) :: String.t()
  def normalize_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> URI.parse()
    |> normalize_uri()
    |> URI.to_string()
  end

  def normalize_url(_), do: raise(ArgumentError, "URL must be a string")

  defp normalize_uri(%URI{} = uri) do
    %URI{
      uri
      | scheme: normalize_scheme(uri.scheme),
        host: normalize_host(uri.host),
        path: normalize_path(uri.path)
    }
  end

  defp normalize_scheme(nil), do: "https"
  defp normalize_scheme(scheme), do: String.downcase(scheme)

  defp normalize_host(nil), do: nil
  defp normalize_host(host), do: String.downcase(host)

  defp normalize_path(nil), do: "/"
  defp normalize_path(""), do: "/"
  defp normalize_path("/"), do: "/"
  defp normalize_path(path), do: String.trim_trailing(path, "/")
end
