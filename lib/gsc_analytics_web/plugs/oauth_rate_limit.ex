defmodule GscAnalyticsWeb.Plugs.OAuthRateLimit do
  @moduledoc """
  Throttles repeated OAuth requests to prevent state/session abuse.
  """

  import Plug.Conn

  @window_ms 60_000
  @max_requests 10

  def init(opts), do: opts

  def call(conn, _opts) do
    bucket = "oauth:" <> ip_bucket(conn)

    case Hammer.check_rate(bucket, @window_ms, @max_requests) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(:too_many_requests)
        |> Phoenix.Controller.text("Too many OAuth attempts. Please try again in a minute.")
        |> halt()
    end
  end

  defp ip_bucket(%Plug.Conn{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> IO.chardata_to_string()
  end

  defp ip_bucket(_conn), do: "unknown"
end
