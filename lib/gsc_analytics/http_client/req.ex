defmodule GscAnalytics.HTTPClient.Req do
  @moduledoc """
  Default HTTP client implementation backed by Req.
  """

  @behaviour GscAnalytics.HTTPClient

  @impl true
  def post(url, opts \\ []) do
    Req.post(url, opts)
  end
end
