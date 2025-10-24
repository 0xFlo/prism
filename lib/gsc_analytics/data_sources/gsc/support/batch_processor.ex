defmodule GscAnalytics.DataSources.GSC.Support.BatchProcessor do
  @moduledoc """
  Handles all batch request processing for Google Search Console API.

  This module provides a streamlined interface for executing batch requests
  against the Google API, delegating complex parsing to MultipartParser and
  retry logic to RetryHelper.

  ## Features

  - Multipart HTTP batch request construction
  - Response validation and classification
  - Automatic retry with exponential backoff
  - Telemetry integration for audit logging
  """

  require Logger

  alias GscAnalytics.DataSources.GSC.Support.{MultipartParser, RetryHelper, DataHelpers}
  alias GscAnalytics.DataSources.GSC.Core.Config
  alias GscAnalytics.DataSources.GSC.Telemetry.AuditLogger

  @default_base_url "https://www.googleapis.com/batch"
  @default_api_version "webmasters/v3"
  @batch_limit 100

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Execute a batch of requests against the Google API.

  ## Parameters

    - `token` - OAuth2 access token
    - `requests` - List of request maps with :id, :method, :path, :body
    - `operation` - Operation name for logging
    - `opts` - Options including :base_url, :api_version, :timeout

  ## Returns

    - `{:ok, responses, batch_count}` - Successfully executed batch
    - `{:error, reason}` - Batch execution failed
  """
  @spec execute_batch(binary(), list(), String.t(), keyword()) ::
          {:ok, list(), non_neg_integer()} | {:error, term()}
  def execute_batch(token, requests, operation, opts \\ [])

  def execute_batch(_token, [], _operation, _opts), do: {:ok, [], 0}

  def execute_batch(token, requests, operation, opts) when is_list(requests) do
    # Process in chunks respecting Google's batch limit
    chunks = Enum.chunk_every(requests, @batch_limit)
    http_batch_count = length(chunks)

    result =
      chunks
      |> Enum.reduce_while({:ok, []}, fn chunk, {:ok, acc} ->
        case execute_batch_chunk(token, chunk, operation, opts) do
          {:ok, responses} ->
            {:cont, {:ok, [responses | acc]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, response_lists} ->
        # Flatten and reverse to maintain order (O(n) instead of O(n²))
        responses = response_lists |> Enum.reverse() |> List.flatten()
        {:ok, responses, http_batch_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Validate that all expected responses are present and properly formed.
  """
  @spec validate_responses(list(), list()) :: {:ok, map()} | {:error, term()}
  def validate_responses(requests, responses) do
    with {:ok, response_map} <- build_response_map(responses) do
      request_ids = Enum.map(requests, & &1.id)
      response_ids = Map.keys(response_map)

      missing = request_ids -- response_ids
      extra = response_ids -- request_ids

      cond do
        missing != [] -> {:error, {:missing_parts, Enum.sort(missing)}}
        extra != [] -> {:error, {:unexpected_parts, Enum.sort(extra)}}
        true -> {:ok, response_map}
      end
    end
  end

  # ============================================================================
  # Private - Batch Execution
  # ============================================================================

  defp execute_batch_chunk(token, chunk, operation, opts) do
    base_url = Keyword.get(opts, :base_url, @default_base_url)
    api_version = Keyword.get(opts, :api_version, @default_api_version)
    timeout = Keyword.get(opts, :timeout, Config.http_timeout())

    # Use RetryHelper for retry logic
    RetryHelper.with_retry(
      fn ->
        execute_single_batch(token, chunk, base_url, api_version, timeout, operation)
      end,
      max_retries: Config.max_retries(),
      retry_on: &retryable_error?/1,
      on_retry: fn attempt, reason ->
        Logger.debug("Batch retry #{attempt + 1}: #{RetryHelper.format_retry_reason(reason)}")
      end
    )
  end

  defp execute_single_batch(token, chunk, base_url, api_version, timeout, operation) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, resp_headers, resp_body} <-
           do_http_batch(token, chunk, base_url, api_version, timeout),
         {:ok, parsed_responses} <-
           MultipartParser.parse(resp_headers, resp_body),
         {:ok, validated_responses} <-
           validate_and_log_responses(chunk, parsed_responses, operation, start_time) do
      {:ok, validated_responses}
    else
      {:error, :token_refresh_needed} ->
        # Special case - need new token
        {:error, :token_refresh_needed}

      error ->
        error
    end
  end

  defp retryable_error?({:error, :token_refresh_needed}), do: false
  defp retryable_error?({:error, :unauthorized}), do: false
  defp retryable_error?({:error, {:rate_limited, _}}), do: true
  defp retryable_error?({:error, {:server_error, _, _}}), do: true

  defp retryable_error?({:error, {:http_error, status, _}}) when status == 429 or status >= 500,
    do: true

  defp retryable_error?({:error, {:batch_request_failed, _}}), do: true
  defp retryable_error?(_), do: false

  # ============================================================================
  # Private - HTTP Transport
  # ============================================================================

  defp do_http_batch(token, requests, base_url, api_version, timeout) do
    boundary = DataHelpers.build_batch_boundary()
    body = build_multipart_body(requests, boundary)

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "multipart/mixed; boundary=#{boundary}"},
      {"Accept", "multipart/mixed"}
    ]

    request = {
      String.to_charlist("#{base_url}/#{api_version}"),
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end),
      String.to_charlist("multipart/mixed; boundary=#{boundary}"),
      body
    }

    case :httpc.request(:post, request, [{:timeout, timeout}], []) do
      {:ok, {{_, 200, _}, resp_headers, resp_body}} ->
        {:ok, resp_headers, resp_body}

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, :unauthorized}

      {:ok, {{_, status, _}, _, resp_body}} ->
        {:error, {:http_error, status, to_string(resp_body)}}

      {:error, reason} ->
        {:error, {:batch_request_failed, reason}}
    end
  end

  # ============================================================================
  # Private - Request Building
  # ============================================================================

  defp build_multipart_body(requests, boundary) do
    parts =
      Enum.map(requests, fn request ->
        build_request_part(request, boundary)
      end)

    IO.iodata_to_binary([parts, "--", boundary, "--\r\n"])
  end

  defp build_request_part(request, boundary) do
    method = request.method || :post
    method_str = method |> to_string() |> String.upcase()
    json_body = JSON.encode!(request.body)
    content_length = byte_size(json_body)

    [
      "--",
      boundary,
      "\r\n",
      "Content-Type: application/http\r\n",
      "Content-ID: <",
      request.id,
      ">\r\n",
      "\r\n",
      method_str,
      " ",
      request.path,
      " HTTP/1.1\r\n",
      "Content-Type: application/json\r\n",
      "Content-Length: ",
      Integer.to_string(content_length),
      "\r\n",
      "\r\n",
      json_body,
      "\r\n"
    ]
  end

  # ============================================================================
  # Private - Response Validation & Logging
  # ============================================================================

  defp validate_and_log_responses(requests, responses, operation, start_time) do
    with {:ok, response_map} <- validate_responses(requests, responses) do
      duration_ms = System.monotonic_time(:millisecond) - start_time

      logged_responses =
        Enum.map(requests, fn request ->
          part = Map.fetch!(response_map, request.id)
          log_batch_part(operation, request, part, duration_ms)

          Map.merge(part, %{
            site_url: request.site_url,
            metadata: request.metadata || %{},
            duration_ms: duration_ms
          })
        end)

      # Check if any responses have errors
      case classify_responses(logged_responses) do
        :ok ->
          {:ok, logged_responses}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp log_batch_part(operation, request, part, duration_ms) do
    row_count = DataHelpers.extract_row_count(part.body)

    metadata =
      (request.metadata || %{})
      |> Map.new()
      |> Map.merge(%{
        site_url: request.site_url,
        batch: true,
        status: part.status,
        rate_limited: part.status == 429
      })

    metadata =
      if part.status >= 400 do
        Map.put(metadata, :error, String.slice(part.raw_body || "", 0, 160))
      else
        metadata
      end

    AuditLogger.log_api_request(operation, %{duration_ms: duration_ms, rows: row_count}, metadata)
  end

  defp classify_responses(responses) do
    case Enum.find(responses, &(&1.status >= 400)) do
      nil ->
        :ok

      %{status: 401} ->
        {:error, :unauthorized}

      %{status: 429, id: id} ->
        {:error, {:rate_limited, id}}

      %{status: status, id: id} when status >= 500 ->
        {:error, {:server_error, status, id}}

      %{id: id, status: status, raw_body: raw} ->
        {:error, {:batch_response_error, id, status, raw}}
    end
  end

  defp build_response_map(responses) do
    Enum.reduce_while(responses, {:ok, %{}}, fn response, {:ok, acc} ->
      case response do
        %{id: nil} ->
          {:halt, {:error, {:invalid_part, response}}}

        %{id: id} when is_binary(id) or is_atom(id) ->
          key = DataHelpers.normalize_id(id)

          if Map.has_key?(acc, key) do
            {:halt, {:error, {:duplicate_parts, key}}}
          else
            {:cont, {:ok, Map.put(acc, key, Map.put(response, :id, key))}}
          end

        %{id: id} ->
          {:halt, {:error, {:invalid_part, id}}}
      end
    end)
  end
end
