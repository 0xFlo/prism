defmodule GscAnalytics.DataSources.GSC.Support.RetryHelper do
  @moduledoc """
  Common retry logic and exponential backoff calculations for GSC API operations.

  Consolidates retry patterns that were duplicated across Client and BatchProcessor.
  """

  require Logger
  alias GscAnalytics.DataSources.GSC.Core.Config

  @doc """
  Calculate exponential backoff delay for a given attempt number.

  ## Examples

      iex> calculate_backoff(0)
      1000

      iex> calculate_backoff(1)
      2000

      iex> calculate_backoff(2)
      4000
  """
  @spec calculate_backoff(non_neg_integer(), pos_integer()) :: pos_integer()
  def calculate_backoff(attempt, base_delay \\ nil) do
    base = base_delay || Config.retry_delay()
    (base * :math.pow(2, attempt)) |> round()
  end

  @doc """
  Execute a function with automatic retry on failure.

  ## Options
    - `:max_retries` - Maximum number of retry attempts (default: from Config)
    - `:base_delay` - Base delay for exponential backoff (default: from Config)
    - `:retry_on` - Function to determine if error is retryable (default: always retry)
    - `:on_retry` - Callback function called before each retry

  ## Examples

      with_retry(fn -> make_api_call() end,
        max_retries: 3,
        retry_on: fn
          {:error, :rate_limited} -> true
          {:error, {:http_error, status, _}} when status >= 500 -> true
          _ -> false
        end
      )
  """
  @spec with_retry(function(), keyword()) :: {:ok, term()} | {:error, term()}
  def with_retry(operation, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, Config.max_retries())
    retry_on = Keyword.get(opts, :retry_on, fn _ -> true end)
    on_retry = Keyword.get(opts, :on_retry, fn _, _ -> :ok end)

    do_retry(operation, retry_on, on_retry, 0, max_retries, opts)
  end

  @doc """
  Decode a JSON response body with consistent error handling.

  Used to consolidate the duplicated JSON decode pattern across modules.
  """
  @spec decode_json_response(iodata()) :: {:ok, term()} | {:error, {:decode_error, term()}}
  def decode_json_response(response_body) do
    case JSON.decode(to_string(response_body)) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:decode_error, reason}}
    end
  end

  @doc """
  Format a retry reason for logging.
  """
  @spec format_retry_reason(term()) :: String.t()
  def format_retry_reason({:server_error, status, id}), do: "server_error #{status} (#{id})"
  def format_retry_reason({:rate_limited, id}), do: "rate_limited (#{id})"
  def format_retry_reason({:http_error, status, _}), do: "http_error #{status}"
  def format_retry_reason({:request_failed, reason}), do: "request_failed #{inspect(reason)}"
  def format_retry_reason(:unauthorized), do: "unauthorized"
  def format_retry_reason(:token_refresh_needed), do: "token_refresh_needed"
  def format_retry_reason(other), do: inspect(other)

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_retry(operation, _retry_on, _on_retry, attempt, max_retries, _opts)
       when attempt >= max_retries do
    case operation.() do
      {:error, reason} = error ->
        Logger.debug(
          "Final attempt failed after #{attempt} retries: #{format_retry_reason(reason)}"
        )

        error

      success ->
        success
    end
  end

  defp do_retry(operation, retry_on, on_retry, attempt, max_retries, opts) do
    case operation.() do
      {:error, reason} = error ->
        if retry_on.(error) do
          delay = calculate_backoff(attempt, opts[:base_delay])

          Logger.debug(
            "Retry #{attempt + 1}/#{max_retries} after #{delay}ms: #{format_retry_reason(reason)}"
          )

          on_retry.(attempt, reason)
          Process.sleep(delay)
          do_retry(operation, retry_on, on_retry, attempt + 1, max_retries, opts)
        else
          error
        end

      success ->
        success
    end
  end
end
