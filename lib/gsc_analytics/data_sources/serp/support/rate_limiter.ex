defmodule GscAnalytics.DataSources.SERP.Support.RateLimiter do
  @moduledoc """
  Rate limiting for ScrapFly SERP API requests.

  Uses Hammer for distributed rate limiting with ETS backend.
  Tracks API credit usage per account to prevent quota exhaustion.

  ## Configuration
  - Rate limit: 60 requests per minute (configurable via Config)
  - Cost tracking: Stores in ETS table for fast access

  ## Example Usage
      iex> RateLimiter.check_rate("account_1")
      :ok

      iex> RateLimiter.track_cost("account_1", 36)
      :ok

      iex> RateLimiter.get_total_cost("account_1")
      36
  """

  alias GscAnalytics.DataSources.SERP.Core.Config

  @ets_table :serp_api_costs

  @doc """
  Initialize the ETS table for cost tracking.
  Called automatically on first use.

  Uses rescue pattern to handle concurrent initialization attempts
  across multiple processes or nodes.
  """
  def init_ets do
    unless :ets.whereis(@ets_table) != :undefined do
      try do
        :ets.new(@ets_table, [:named_table, :public, :set])
      rescue
        ArgumentError ->
          # Table was created by another process between check and creation
          # This is safe to ignore as the table now exists
          :ok
      end
    end

    :ok
  end

  @doc """
  Check if a request is allowed under the current rate limit.

  Uses Hammer to enforce per-account rate limiting based on configured limit.

  ## Parameters
  - `account_id` - Account identifier (string or integer)

  ## Returns
  - `:ok` - Request is allowed
  - `{:error, :rate_limited}` - Rate limit exceeded

  ## Example
      iex> RateLimiter.check_rate("account_123")
      :ok

      # After 60 requests in a minute:
      iex> RateLimiter.check_rate("account_123")
      {:error, :rate_limited}
  """
  def check_rate(account_id) do
    bucket_key = "serp:api:#{account_id}"
    rate_limit = Config.rate_limit_per_minute()

    case Hammer.check_rate(bucket_key, 60_000, rate_limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  @doc """
  Check rate limit and return remaining quota information.

  ## Parameters
  - `account_id` - Account identifier

  ## Returns
  - `{:ok, remaining}` - Request allowed, returns remaining requests
  - `{:error, :rate_limited}` - Rate limit exceeded

  ## Example
      iex> RateLimiter.check_rate_with_info("account_123")
      {:ok, 59}
  """
  def check_rate_with_info(account_id) do
    bucket_key = "serp:api:#{account_id}"
    rate_limit = Config.rate_limit_per_minute()

    case Hammer.check_rate(bucket_key, 60_000, rate_limit) do
      {:allow, count} ->
        remaining = max(0, rate_limit - count)
        {:ok, remaining}

      {:deny, _limit} ->
        {:error, :rate_limited}
    end
  end

  @doc """
  Track API credits used for an account.

  Accumulates credits in ETS table for cost monitoring.

  ## Parameters
  - `account_id` - Account identifier
  - `credits` - Number of API credits used (default: 36 for SERP+LLM)

  ## Returns
  - `:ok`

  ## Example
      iex> RateLimiter.track_cost(1, 36)
      :ok
  """
  def track_cost(account_id, credits) when is_integer(credits) do
    init_ets()

    key = {:cost, account_id}

    :ets.update_counter(@ets_table, key, {2, credits}, {key, 0})

    :ok
  end

  @doc """
  Get total API credits used for an account.

  ## Parameters
  - `account_id` - Account identifier

  ## Returns
  - Integer - Total credits used

  ## Example
      iex> RateLimiter.get_total_cost(1)
      72
  """
  def get_total_cost(account_id) do
    init_ets()

    key = {:cost, account_id}

    case :ets.lookup(@ets_table, key) do
      [{^key, cost}] -> cost
      [] -> 0
    end
  end

  @doc """
  Get remaining quota for an account's rate limit window.

  ## Parameters
  - `account_id` - Account identifier

  ## Returns
  - Integer - Remaining requests in current window

  ## Example
      iex> RateLimiter.get_remaining_quota("account_123")
      60
  """
  def get_remaining_quota(account_id) do
    bucket_key = "serp:api:#{account_id}"
    rate_limit = Config.rate_limit_per_minute()

    case Hammer.inspect_bucket(bucket_key, 60_000, rate_limit) do
      {:ok, {count, _count_remaining, _ms_to_next_bucket, _created_at, _updated_at}} ->
        max(0, rate_limit - count)

      _ ->
        rate_limit
    end
  end

  @doc """
  Reset rate limit for an account.

  Useful for testing or manual quota resets.

  ## Parameters
  - `account_id` - Account identifier

  ## Returns
  - `:ok`

  ## Example
      iex> RateLimiter.reset_rate_limit("account_123")
      :ok
  """
  def reset_rate_limit(account_id) do
    bucket_key = "serp:api:#{account_id}"

    case Hammer.delete_buckets(bucket_key) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
