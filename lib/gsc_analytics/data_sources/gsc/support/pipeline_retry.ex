defmodule GscAnalytics.DataSources.GSC.Support.PipelineRetry do
  @moduledoc """
  Helper for executing retry policies with exponential backoff.
  """

  def retry(fun, max_attempts, base_delay_ms)
      when is_function(fun, 0) and max_attempts >= 0 and base_delay_ms >= 0 do
    do_retry(fun, max_attempts, base_delay_ms, 0)
  end

  defp do_retry(fun, max_attempts, base_delay_ms, attempt) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, {:rate_limited, wait_ms}} when attempt < max_attempts ->
        Process.sleep(wait_ms)
        do_retry(fun, max_attempts, base_delay_ms, attempt + 1)

      {:error, _reason} when attempt < max_attempts ->
        backoff = trunc(base_delay_ms * :math.pow(2, attempt))
        Process.sleep(max(backoff, base_delay_ms))
        do_retry(fun, max_attempts, base_delay_ms, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
