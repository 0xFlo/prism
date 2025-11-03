defmodule GscAnalytics.DataSources.GSC.Core.Client do
  @moduledoc """
  High-level Google Search Console API client.

  This module provides a focused interface for GSC API operations,
  delegating batch processing to BatchProcessor and authentication
  to the Authenticator GenServer.

  ## Features

  - Simple API methods for fetching URL and query data
  - Automatic authentication and token refresh
  - Built-in rate limiting and retry logic
  - Telemetry integration for monitoring
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Support.{Authenticator, RateLimiter, BatchProcessor}
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger
  alias GscAnalytics.DataSources.GSC.Core.Config

  @base_url "https://www.googleapis.com/webmasters"
  @api_version "v3"
  @max_retries 3
  @retry_delay 1_000

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Fetch performance data for a specific URL.

  ## Options
    - `:dimensions` - List of dimensions to group by (default: ["page"])
    - `:start_date` - Start date in YYYY-MM-DD format
    - `:end_date` - End date in YYYY-MM-DD format
    - `:row_limit` - Maximum rows to return (default: 1)
    - `:data_state` - "final" or "all" (default: "final")
  """
  def fetch_url_performance(account_id, site_url, url, opts \\ []) do
    start_date = opts[:start_date] || default_start_date()
    end_date = opts[:end_date] || default_end_date()

    request_body = %{
      "startDate" => start_date,
      "endDate" => end_date,
      "dimensions" => opts[:dimensions] || ["page"],
      "dimensionFilterGroups" => [
        %{
          "filters" => [
            %{
              "dimension" => "page",
              "operator" => "equals",
              "expression" => url
            }
          ]
        }
      ],
      "rowLimit" => opts[:row_limit] || 1,
      "dataState" => opts[:data_state] || "final"
    }

    with :ok <- RateLimiter.check_rate(account_id, site_url),
         {:ok, response} <- execute_api_request(account_id, site_url, request_body) do
      parse_performance_response(url, response, start_date, end_date)
    else
      {:error, :rate_limited, wait_time} = error ->
        Logger.warning("Rate limited, retry after #{wait_time}ms")
        error

      {:error, reason} = error ->
        Logger.error("Failed to fetch performance for #{url}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Fetch ALL URLs with performance data for a specific date.

  Returns all URLs that had impressions on that date.
  """
  def fetch_all_urls_for_date(account_id, site_url, date, opts \\ []) do
    dimensions = if opts[:include_queries], do: ["page", "query"], else: ["page"]

    fetch_search_analytics_data(
      account_id,
      site_url,
      date,
      dimensions,
      opts,
      "fetch_all_urls"
    )
  end

  @doc """
  Fetch ALL queries with their URL associations for a specific date.
  """
  def fetch_all_queries_for_date(account_id, site_url, date, opts \\ []) do
    fetch_search_analytics_data(
      account_id,
      site_url,
      date,
      ["page", "query"],
      opts,
      "fetch_all_queries"
    )
  end

  @doc """
  Fetch top search queries for a specific URL.

  ## Options
    - `:limit` - Maximum number of queries to return (default: 10)
    - `:order_by` - Field to order by (default: "clicks")
  """
  def fetch_url_queries(account_id, site_url, url, opts \\ []) do
    start_date = opts[:start_date] || default_start_date()
    end_date = opts[:end_date] || default_end_date()
    limit = opts[:limit] || 10
    order_field = opts[:order_by] || "clicks"

    request_body = %{
      "startDate" => start_date,
      "endDate" => end_date,
      "dimensions" => ["query"],
      "dimensionFilterGroups" => [
        %{
          "filters" => [
            %{
              "dimension" => "page",
              "operator" => "equals",
              "expression" => url
            }
          ]
        }
      ],
      "rowLimit" => limit,
      "orderBy" => [
        %{
          "field" => order_field,
          "order" => "descending"
        }
      ],
      "dataState" => "final"
    }

    with :ok <- RateLimiter.check_rate(account_id, site_url),
         {:ok, response} <- execute_api_request(account_id, site_url, request_body) do
      parse_queries_response(response)
    else
      {:error, reason} = error ->
        Logger.error("Failed to fetch queries for #{url}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Execute a batch of query requests.

  Delegates to BatchProcessor for multipart batch handling.
  """
  def fetch_query_batch(account_id, requests, operation \\ "fetch_queries_batch")
      when is_list(requests) do
    with {:ok, token} <- get_auth_token(account_id) do
      BatchProcessor.execute_batch(token, requests, operation)
    end
  end

  @doc """
  List all properties the service account has access to.
  """
  def list_sites(account_id) do
    with {:ok, token} <- get_auth_token(account_id),
         {:ok, response} <- authenticated_get("/v3/sites", token) do
      parse_sites_response(response)
    end
  end

  # ============================================================================
  # Private - Core Search Analytics
  # ============================================================================

  defp fetch_search_analytics_data(account_id, site_url, date, dimensions, opts, operation_name) do
    start_time = System.monotonic_time(:millisecond)
    date_string = Date.to_iso8601(date)

    request_body = %{
      "startDate" => date_string,
      "endDate" => date_string,
      "dimensions" => dimensions,
      "rowLimit" => Config.page_size(),
      "startRow" => opts[:start_row] || 0,
      "dataState" => "final"
    }

    result =
      with :ok <- RateLimiter.check_rate(account_id, site_url),
           {:ok, response} <- execute_api_request(account_id, site_url, request_body) do
        {:ok, response}
      else
        {:error, :rate_limited, wait_time} = error ->
          Logger.warning("Rate limited for #{operation_name}, retry after #{wait_time}ms")
          error

        {:error, reason} = error ->
          Logger.error("Failed to #{operation_name} for #{date}: #{inspect(reason)}")
          error
      end

    # Log API request for audit
    case result do
      {:ok, response} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time
        row_count = length(Map.get(response, "rows", []))

        AuditLogger.log_api_request(
          operation_name,
          %{duration_ms: duration_ms, rows: row_count},
          %{
            account_id: account_id,
            site_url: site_url,
            date: date_string,
            rate_limited: false
          }
        )

        result

      _ ->
        result
    end
  end

  defp execute_api_request(account_id, site_url, request_body) do
    with {:ok, token} <- get_auth_token(account_id) do
      search_analytics_query(site_url, request_body, token)
    end
  end

  # ============================================================================
  # Private - HTTP Operations
  # ============================================================================

  defp search_analytics_query(site_url, request_body, token, retry_count \\ 0) do
    encoded_site = URI.encode_www_form(site_url)
    url = "#{@base_url}/#{@api_version}/sites/#{encoded_site}/searchAnalytics/query"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    json_body = JSON.encode!(request_body)

    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
      ~c"application/json",
      json_body
    }

    case :httpc.request(:post, request, [{:timeout, Config.http_timeout()}], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case JSON.decode(to_string(response_body)) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, {:decode_error, reason}}
        end

      {:ok, {{_, 429, _}, _, _}} when retry_count < @max_retries ->
        # Rate limited - exponential backoff
        delay = (@retry_delay * :math.pow(2, retry_count)) |> round()
        Logger.info("Rate limited, retrying in #{delay}ms")
        Process.sleep(delay)
        search_analytics_query(site_url, request_body, token, retry_count + 1)

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, :unauthorized}

      {:ok, {{_, 403, _}, _, _}} ->
        {:error, :forbidden}

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("GSC API error #{status}: #{to_string(response_body)}")
        {:error, {:api_error, status, to_string(response_body)}}

      {:error, reason} ->
        if retry_count < @max_retries do
          delay = (@retry_delay * :math.pow(2, retry_count)) |> round()
          Logger.warning("Request failed: #{inspect(reason)}, retrying in #{delay}ms")
          Process.sleep(delay)
          search_analytics_query(site_url, request_body, token, retry_count + 1)
        else
          {:error, {:request_failed, reason}}
        end
    end
  end

  defp authenticated_get(path, token) do
    url = "#{@base_url}#{path}"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/json"}
    ]

    request = {
      String.to_charlist(url),
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
    }

    case :httpc.request(:get, request, [{:timeout, Config.http_timeout()}], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case JSON.decode(to_string(response_body)) do
          {:ok, body} -> {:ok, body}
          {:error, reason} -> {:error, {:decode_error, reason}}
        end

      {:ok, {{_, status, _}, _, response_body}} ->
        {:error, {:api_error, status, to_string(response_body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # ============================================================================
  # Private - Response Parsing
  # ============================================================================

  defp parse_performance_response(url, response, start_date, end_date) do
    case response do
      %{"rows" => [row | _]} ->
        {:ok,
         %{
           url: url,
           clicks: row["clicks"] || 0,
           impressions: row["impressions"] || 0,
           ctr: row["ctr"] || 0.0,
           position: row["position"] || 0.0,
           date_range_start: start_date,
           date_range_end: end_date,
           data_available: true
         }}

      _ ->
        {:ok,
         %{
           url: url,
           clicks: 0,
           impressions: 0,
           ctr: 0.0,
           position: 0.0,
           date_range_start: start_date,
           date_range_end: end_date,
           data_available: false
         }}
    end
  end

  defp parse_queries_response(response) do
    case response do
      %{"rows" => rows} when is_list(rows) ->
        queries =
          Enum.map(rows, fn row ->
            %{
              query: List.first(row["keys"] || [""]),
              clicks: row["clicks"] || 0,
              impressions: row["impressions"] || 0,
              ctr: row["ctr"] || 0.0,
              position: row["position"] || 0.0
            }
          end)

        {:ok, queries}

      _ ->
        {:ok, []}
    end
  end

  defp parse_sites_response(response) do
    case response do
      %{"siteEntry" => sites} when is_list(sites) ->
        site_list =
          Enum.map(sites, fn site ->
            %{
              site_url: site["siteUrl"],
              permission_level: site["permissionLevel"]
            }
          end)

        {:ok, site_list}

      _ ->
        {:ok, []}
    end
  end

  # ============================================================================
  # Private - Authentication
  # ============================================================================

  defp get_auth_token(account_id) do
    try do
      case Authenticator.get_token(account_id) do
        {:ok, token} ->
          {:ok, token}

        {:error, :no_token} ->
          # Token not ready yet, wait and retry once
          Process.sleep(1000)
          Authenticator.get_token(account_id)

        error ->
          error
      end
    catch
      :exit, {:noproc, _} ->
        # Authenticator not started (test mode)
        {:error, :authenticator_not_started}
    end
  end

  # ============================================================================
  # Private - Utilities
  # ============================================================================

  defp default_start_date do
    DateTime.utc_now()
    |> DateTime.add(-31, :day)
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp default_end_date do
    DateTime.utc_now()
    # GSC data has 2-3 day delay
    |> DateTime.add(-3, :day)
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end
end
