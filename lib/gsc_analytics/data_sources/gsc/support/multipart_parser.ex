defmodule GscAnalytics.DataSources.GSC.Support.MultipartParser do
  @moduledoc """
  Handles parsing of multipart HTTP responses from Google Batch API.

  This module extracts the complex multipart parsing logic from BatchProcessor,
  providing a focused, testable interface for parsing batch API responses.
  """

  @doc """
  Parse a multipart batch response from Google API.

  Returns {:ok, parts} where each part has:
  - :id - The Content-ID from the response
  - :status - HTTP status code
  - :headers - Response headers as a map
  - :body - Decoded JSON body (or raw string if not JSON)
  - :raw_body - Original response body
  """
  @spec parse(list(), binary()) :: {:ok, list()} | {:error, term()}
  def parse(resp_headers, resp_body) do
    with {:ok, boundary} <- extract_boundary(resp_headers),
         {:ok, parts} <- decode_multipart_parts(resp_body, boundary) do
      {:ok, parts}
    end
  end

  # ============================================================================
  # Private - Boundary Extraction
  # ============================================================================

  defp extract_boundary(headers) do
    content_type_header =
      Enum.find(headers, fn {key, _value} ->
        String.downcase(to_string(key)) == "content-type"
      end)

    case content_type_header do
      nil ->
        {:error, :missing_boundary}

      {_key, value} ->
        value_str = to_string(value)

        case Regex.run(~r/boundary=([^;]+)/, value_str) do
          [_, boundary] ->
            {:ok,
             boundary |> String.trim() |> String.trim_leading("\"") |> String.trim_trailing("\"")}

          _ ->
            {:error, :missing_boundary}
        end
    end
  end

  # ============================================================================
  # Private - Multipart Decoding
  # ============================================================================

  defp decode_multipart_parts(body, boundary) do
    binary = IO.iodata_to_binary(body)
    delimiter = "--" <> boundary

    segments =
      binary
      |> String.split(delimiter)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or &1 == "--"))

    parts =
      Enum.reduce_while(segments, {:ok, []}, fn segment, {:ok, acc} ->
        case parse_response_part(segment) do
          {:ok, part} -> {:cont, {:ok, [part | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case parts do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response_part(segment) do
    segment = String.trim_leading(segment, "\r\n")

    with [part_headers_raw, inner_raw] <- String.split(segment, "\r\n\r\n", parts: 2),
         {:ok, part_headers} <- parse_header_lines(part_headers_raw),
         {:ok, content_id} <- fetch_content_id(part_headers),
         {:ok, status, inner_headers, body_raw} <- parse_inner_response(inner_raw),
         {:ok, decoded_body} <- decode_part_body(body_raw, inner_headers) do
      {:ok,
       %{
         id: content_id,
         status: status,
         headers: inner_headers,
         body: decoded_body,
         raw_body: body_raw
       }}
    end
  end

  # ============================================================================
  # Private - Header Parsing
  # ============================================================================

  defp parse_header_lines(text) when is_binary(text) do
    text
    |> String.split("\r\n", trim: true)
    |> parse_header_lines_from_list()
  end

  defp parse_header_lines_from_list(lines) when is_list(lines) do
    Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, acc} ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          lowered_key = key |> String.trim() |> String.downcase()
          trimmed_value = value |> String.trim()
          {:cont, {:ok, Map.put(acc, lowered_key, trimmed_value)}}

        _ ->
          if String.trim(line) == "" do
            {:cont, {:ok, acc}}
          else
            {:halt, {:error, {:invalid_header, line}}}
          end
      end
    end)
  end

  defp fetch_content_id(headers) do
    case Map.fetch(headers, "content-id") do
      {:ok, value} ->
        id =
          value
          |> String.trim_leading("<")
          |> String.trim_trailing(">")
          |> String.replace_prefix("response-", "")

        {:ok, id}

      :error ->
        {:error, :missing_content_id}
    end
  end

  # ============================================================================
  # Private - Response Parsing
  # ============================================================================

  defp parse_inner_response(inner_raw) do
    case String.split(inner_raw, "\r\n\r\n", parts: 2) do
      [status_and_headers, body_raw] ->
        [status_line | header_lines] = String.split(status_and_headers, "\r\n", trim: true)

        with {:ok, status} <- parse_status_line(status_line),
             {:ok, headers} <- parse_header_lines_from_list(header_lines) do
          {:ok, status, headers, String.trim_trailing(body_raw)}
        end

      _ ->
        {:error, :invalid_part}
    end
  end

  defp parse_status_line(line) do
    case Regex.run(~r/HTTP\/1\.\d\s+(\d{3})/, line) do
      [_, code] -> {:ok, String.to_integer(code)}
      _ -> {:error, {:invalid_status_line, line}}
    end
  end

  # ============================================================================
  # Private - Body Decoding
  # ============================================================================

  defp decode_part_body(body_raw, headers) do
    trimmed = String.trim_leading(body_raw)

    cond do
      trimmed == "" ->
        {:ok, %{}}

      content_type_json?(headers) ->
        case JSON.decode(trimmed) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:decode_error, reason}}
        end

      true ->
        {:ok, trimmed}
    end
  end

  defp content_type_json?(headers) do
    case Map.get(headers, "content-type") do
      nil -> false
      value -> String.contains?(String.downcase(value), "application/json")
    end
  end
end
