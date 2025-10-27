defmodule GscAnalytics.DataSources.GSC.Support.RateLimiter do
  @moduledoc """
  Simple rate limiter for Google Search Console API using Hammer.

  GSC allows 1,200 queries per minute per site.
  """

  require Logger
  alias GscAnalytics.DataSources.GSC.Accounts

  @queries_per_minute 1_200
  # 1 minute in milliseconds
  @window_ms 60_000

  @doc """
  Check if a request can proceed for the given account + site.
  Returns :ok if allowed, or {:error, :rate_limited, wait_time_ms} if denied.
  """
  @spec check_rate(integer(), String.t() | nil) ::
          :ok | {:error, :rate_limited, non_neg_integer()} | {:error, term()}
  def check_rate(account_id, site_url \\ nil) when is_integer(account_id) do
    with {:ok, site} <- resolve_site(account_id, site_url) do
      bucket = "gsc:#{account_id}:#{site}"

      case Hammer.check_rate(bucket, @window_ms, @queries_per_minute) do
        {:allow, _count} ->
          :ok

        {:deny, _limit} ->
          Logger.warning(
            "Rate limited for #{site} (account #{account_id}), retry in #{@window_ms}ms"
          )

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
      bucket = "gsc:#{account_id}:#{site}"

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
    case Accounts.default_property(account_id) do
      {:ok, property} -> {:ok, property}
      {:error, reason} -> {:error, reason}
    end
  end
end
