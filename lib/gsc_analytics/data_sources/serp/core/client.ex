defmodule GscAnalytics.DataSources.SERP.Core.Client do
  @moduledoc """
  Req-based HTTP client for ScrapFly SERP API.

  **IMPORTANT:** Uses Req (Prism standard), NOT :httpc.

  ## Usage

      iex> Client.scrape_google("elixir programming")
      {:ok, %{"result" => %{"content" => ...}}}

  """

  alias GscAnalytics.DataSources.SERP.Core.Config

  @max_retries 3
  @retry_delay 1_000

  @doc """
  Scrape Google SERP for a given keyword.

  Returns `{:ok, json_response}` or `{:error, reason}`.

  ## Examples

      iex> Client.scrape_google("elixir programming")
      {:ok, %{"result" => ...}}

      iex> Client.scrape_google("test", geo: "uk")
      {:ok, %{"result" => ...}}

      iex> Client.scrape_google("test", extraction_prompt: "Extract position...")
      {:ok, %{"result" => %{"extracted_data" => ...}}}

  """
  def scrape_google(keyword, opts \\ []) when is_binary(keyword) do
    geo = opts[:geo]
    extraction_prompt = opts[:extraction_prompt]
    params = build_params(keyword, geo, extraction_prompt)
    request_url = "#{Config.base_url()}/scrape"

    execute_request(request_url, params)
  end

  @doc """
  Build Google search URL with query parameters.

  ## Examples

      iex> Client.build_search_url("test query", "us")
      "https://www.google.com/search?q=test+query&gl=us&hl=en"

  """
  def build_search_url(keyword, geo) do
    query_params =
      URI.encode_query(%{
        "q" => keyword,
        "gl" => geo,
        "hl" => "en"
      })

    "https://www.google.com/search?#{query_params}"
  end

  @doc """
  Build ScrapFly API request parameters.

  ## Examples

      iex> Client.build_params("test query", "us", nil)
      %{
        "key" => "api_key",
        "url" => "https://www.google.com/search?...",
        "country" => "us",
        "format" => "json",
        "render_js" => "true",
        "asp" => "true"
      }

  """
  def build_params(keyword, geo, extraction_prompt \\ nil) do
    geo = geo || Config.default_geo()
    search_url = build_search_url(keyword, geo)

    base_params = %{
      "key" => Config.api_key(),
      "url" => search_url,
      "country" => geo,
      "format" => "json",
      "render_js" => "true",
      "asp" => "true"
    }

    if extraction_prompt do
      Map.put(base_params, "extraction_prompt", extraction_prompt)
    else
      base_params
    end
  end

  @doc """
  Calculate exponential backoff delay for retries.

  ## Examples

      iex> Client.calculate_backoff_delay(0)
      1000

      iex> Client.calculate_backoff_delay(1)
      2000

      iex> Client.calculate_backoff_delay(2)
      4000

  """
  def calculate_backoff_delay(retry_count) do
    (@retry_delay * :math.pow(2, retry_count)) |> round()
  end

  # Private Functions

  defp execute_request(url, params, retry_count \\ 0) do
    start_time = System.monotonic_time(:millisecond)
    http_client = Config.http_client()

    result =
      case http_client.get(url, params: params) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: 429}} when retry_count < @max_retries ->
          delay = calculate_backoff_delay(retry_count)
          Process.sleep(delay)
          execute_request(url, params, retry_count + 1)

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, _reason} when retry_count < @max_retries ->
          delay = calculate_backoff_delay(retry_count)
          Process.sleep(delay)
          execute_request(url, params, retry_count + 1)

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time
    emit_telemetry(result, duration_ms, retry_count)

    result
  end

  defp emit_telemetry(result, duration_ms, retry_count) do
    metadata = %{
      duration_ms: duration_ms,
      retry_count: retry_count,
      success: match?({:ok, _}, result)
    }

    :telemetry.execute(
      [:gsc_analytics, :serp, :api_request],
      %{duration: duration_ms},
      metadata
    )
  end
end
