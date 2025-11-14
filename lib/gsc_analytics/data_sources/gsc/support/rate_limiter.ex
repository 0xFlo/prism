defmodule GscAnalytics.DataSources.GSC.Support.RateLimiter do
  @moduledoc """
  Hammer-backed rate limiter for Google Search Console API calls.

  Enforces Google's 1,200 queries-per-minute quota per site and emits telemetry
  events when the usage approaches or exceeds the budget.
  """

  require Logger

  alias GscAnalytics.Accounts

  @queries_per_minute 1_200
  @window_ms 60_000
  @approaching_ratio 0.8
  @telemetry_prefix [:gsc_analytics, :rate_limit]

  @doc """
  Check if `request_count` queries can proceed for the given account/site.

  Returns `:ok` if allowed or `{:error, :rate_limited, wait_time_ms}` when denied.
  """
  @spec check_rate(integer(), String.t() | nil, pos_integer()) ::
          :ok | {:error, :rate_limited, non_neg_integer()} | {:error, term()}
  def check_rate(account_id, site_url \\ nil, request_count \\ 1)

  def check_rate(account_id, site_url, request_count) when is_integer(account_id) do
    count = max(request_count, 1)

    with {:ok, site} <- resolve_site(account_id, site_url) do
      bucket = bucket_key(account_id, site)

      case Hammer.check_rate_inc(bucket, @window_ms, @queries_per_minute, count) do
        {:allow, current} ->
          emit_usage(account_id, site, current)
          maybe_emit_approaching(account_id, site, current)
          :ok

        {:deny, _limit} ->
          Logger.warning(
            "Rate limited for #{site} (account #{account_id}), retry in #{@window_ms}ms"
          )

          emit_exceeded(account_id, site)
          {:error, :rate_limited, @window_ms}
      end
    end
  end

  @doc """
  Check remaining capacity for the given site.
  """
  @spec get_remaining(integer(), String.t() | nil) :: non_neg_integer() | {:error, term()}
  def get_remaining(account_id, site_url \\ nil) when is_integer(account_id) do
    with {:ok, site} <- resolve_site(account_id, site_url) do
      bucket = bucket_key(account_id, site)

      case Hammer.inspect_bucket(bucket, @window_ms, @queries_per_minute) do
        {:ok, {_count, used, _ms_to_next_bucket, _created, _updated}} ->
          @queries_per_minute - used

        _ ->
          @queries_per_minute
      end
    end
  end

  defp resolve_site(_account_id, site) when is_binary(site) and site != "", do: {:ok, site}

  defp resolve_site(account_id, _site_url) do
    case Accounts.get_active_property_url(account_id) do
      {:ok, property_url} -> {:ok, property_url}
      {:error, reason} -> {:error, reason}
    end
  end

  defp bucket_key(account_id, site), do: "gsc:#{account_id}:#{site}"

  defp maybe_emit_approaching(account_id, site, current) do
    ratio = current / @queries_per_minute

    if ratio >= @approaching_ratio do
      :telemetry.execute(
        @telemetry_prefix ++ [:approaching],
        %{count: 1},
        %{account_id: account_id, site_url: site, limit: @queries_per_minute}
      )
    end
  end

  defp emit_exceeded(account_id, site) do
    :telemetry.execute(
      @telemetry_prefix ++ [:exceeded],
      %{count: 1},
      %{account_id: account_id, site_url: site, retry_ms: @window_ms}
    )
  end

  defp emit_usage(account_id, site, current) do
    :telemetry.execute(
      @telemetry_prefix ++ [:usage],
      %{count: current},
      %{account_id: account_id, site_url: site}
    )
  end
end
