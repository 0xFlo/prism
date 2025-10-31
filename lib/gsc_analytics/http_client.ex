defmodule GscAnalytics.HTTPClient do
  @moduledoc """
  Behaviour for HTTP clients used across the application.

  Abstracting the client enables deterministic testing via Mox while
  allowing Req + Finch in production.
  """

  @callback post(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
end
