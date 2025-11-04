defmodule GscAnalytics.Crawler.HttpStatus do
  @moduledoc """
  HTTP status checking for URLs with redirect following.

  This module validates URL health by checking HTTP status codes,
  following redirects, and detecting broken links or redirect loops.

  ## Features
  - GET request for accurate SEO/redirect detection (matches Google/browsers)
  - Automatic redirect following (max depth 10)
  - Redirect loop detection
  - Relative URL resolution
  - Error handling for timeouts, SSL, DNS failures
  """

  require Logger

  alias GscAnalytics.DateTime, as: AppDateTime

  @default_timeout 10_000
  @default_max_redirects 10
  @redirect_statuses [301, 302, 307, 308]

  @type redirect_chain :: %{optional(String.t()) => String.t()}

  @type check_result :: %{
          status: integer() | nil,
          redirect_url: String.t() | nil,
          redirect_chain: redirect_chain(),
          checked_at: DateTime.t(),
          error: String.t() | nil
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Check the HTTP status of a URL.

  ## Options
    - `:timeout` - Request timeout in milliseconds (default: #{@default_timeout})
    - `:max_redirects` - Maximum redirect depth to follow (default: #{@default_max_redirects})

  ## Returns
    - `{:ok, result}` - Successfully checked (even if URL is broken)
    - `{:error, reason}` - Request failed

  ## Examples

      iex> check_url("https://example.com")
      {:ok,
       %{
         status: 200,
         redirect_url: nil,
         redirect_chain: %{},
         checked_at: ~U[...],
         error: nil
       }}

      iex> check_url("https://example.com/old-page")
      {:ok,
       %{
         status: 301,
         redirect_url: "https://example.com/new-page",
         redirect_chain: %{
           "step_1" => "https://example.com/old-page",
           "step_2" => "https://example.com/new-page"
         },
         checked_at: ~U[...],
         error: nil
       }}

      iex> check_url("https://example.com/not-found")
      {:ok,
       %{
         status: 404,
         redirect_url: nil,
         redirect_chain: %{},
         checked_at: ~U[...],
         error: nil
       }}
  """
  @spec check_url(String.t(), keyword()) :: {:ok, check_result()}
  def check_url(url, opts \\ []) when is_binary(url) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_redirects = Keyword.get(opts, :max_redirects, @default_max_redirects)

    result = follow_redirects(url, [], 0, max_redirects, timeout)

    case result do
      {:ok, status, final_url, chain} ->
        {:ok, build_result(status, final_url, chain, url)}

      {:error, reason} ->
        Logger.warning("Failed to check URL #{url}: #{inspect(reason)}")
        {:ok, build_error_result(url, reason)}
    end
  end

  # ============================================================================
  # Private - Redirect Following
  # ============================================================================

  defp follow_redirects(url, chain, depth, max_depth, timeout) do
    cond do
      depth >= max_depth ->
        {:error, :too_many_redirects}

      url in chain ->
        {:error, :redirect_loop}

      true ->
        case get_request(url, timeout) do
          {:ok, status, headers} when status in @redirect_statuses ->
            location = get_header(headers, "location")

            if location do
              absolute_url = resolve_url(url, location)

              case follow_redirects(absolute_url, chain ++ [url], depth + 1, max_depth, timeout) do
                {:ok, _final_status, final_url, final_chain} when depth == 0 ->
                  # We're checking the original URL - preserve the initial redirect status
                  # This is critical for SEO: we want to see 301, not the final 200
                  {:ok, status, final_url, final_chain}

                result ->
                  # We're in the middle of a redirect chain - pass through
                  result
              end
            else
              # Redirect without Location header - treat as final
              {:ok, status, nil, chain}
            end

          {:ok, status, _headers} ->
            # Non-redirect status - this is the final destination
            final_url = if chain == [], do: nil, else: url
            {:ok, status, final_url, chain}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # Private - HTTP Operations
  # ============================================================================

  defp get_request(url, timeout) do
    # Ensure httpc is started (idempotent)
    :inets.start()
    :ssl.start()

    url_charlist = String.to_charlist(url)

    # Add comprehensive headers to mimic legitimate browser/crawler behavior
    headers = [
      {~c"user-agent", ~c"Mozilla/5.0 (compatible; GSCAnalytics/1.0; URL Health Monitor)"},
      {~c"accept", ~c"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {~c"accept-language", ~c"en-US,en;q=0.9"}
    ]

    request = {url_charlist, headers}

    # Disable automatic redirect following so we can detect and track redirects manually
    # This is critical for SEO - we need to see 301/302 status codes, not the final 200
    http_options = [
      {:timeout, timeout},
      {:autoredirect, false}
    ]

    case :httpc.request(:get, request, http_options, []) do
      {:ok, {{_version, status, _reason}, headers, _body}} ->
        {:ok, status, headers}

      {:error, {:failed_connect, _}} ->
        {:error, :connection_failed}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, {:tls_alert, _}} ->
        {:error, :ssl_error}

      {:error, :nxdomain} ->
        {:error, :dns_error}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn {key, _value} ->
      key
      |> to_string()
      |> String.downcase() ==
        String.downcase(name)
    end)
    |> case do
      {_key, value} -> to_string(value)
      nil -> nil
    end
  end

  # ============================================================================
  # Private - URL Resolution
  # ============================================================================

  defp resolve_url(base_url, relative_url) do
    # Handle absolute URLs
    if String.starts_with?(relative_url, ["http://", "https://"]) do
      relative_url
    else
      base_uri = URI.parse(base_url)

      # Handle protocol-relative URLs (//example.com/path)
      cond do
        String.starts_with?(relative_url, "//") ->
          "#{base_uri.scheme}:#{relative_url}"

        String.starts_with?(relative_url, "/") ->
          # Absolute path
          "#{base_uri.scheme}://#{base_uri.host}#{relative_url}"

        true ->
          # Relative path - resolve against base path
          base_path = base_uri.path || "/"
          base_dir = Path.dirname(base_path)
          resolved_path = Path.join(base_dir, relative_url)
          "#{base_uri.scheme}://#{base_uri.host}#{resolved_path}"
      end
    end
  end

  # ============================================================================
  # Private - Result Building
  # ============================================================================

  defp build_result(status, final_url, chain, _original_url) do
    %{
      status: status,
      redirect_url: final_url,
      redirect_chain: build_chain_map(chain, final_url),
      checked_at: AppDateTime.utc_now(),
      error: nil
    }
  end

  defp build_error_result(_url, reason) do
    error_message = format_error(reason)

    %{
      status: nil,
      redirect_url: nil,
      redirect_chain: %{},
      checked_at: AppDateTime.utc_now(),
      error: error_message
    }
  end

  defp build_chain_map([], _final_url), do: %{}

  defp build_chain_map(chain, final_url) do
    steps =
      chain
      |> Enum.with_index(1)
      |> Enum.map(fn {url, index} ->
        {"step_#{index}", url}
      end)
      |> Map.new()

    final_step =
      if final_url do
        %{"step_#{length(chain) + 1}" => final_url}
      else
        %{}
      end

    Map.merge(steps, final_step)
  end

  defp format_error(:timeout), do: "Request timeout"
  defp format_error(:connection_failed), do: "Connection failed"
  defp format_error(:ssl_error), do: "SSL/TLS error"
  defp format_error(:dns_error), do: "DNS resolution failed"
  defp format_error(:too_many_redirects), do: "Too many redirects (>10)"
  defp format_error(:redirect_loop), do: "Redirect loop detected"
  defp format_error({:http_error, reason}), do: "HTTP error: #{inspect(reason)}"
end
