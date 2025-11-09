defmodule GscAnalytics.DataSources.SERP.Adapters.ReqClient do
  @moduledoc """
  Production HTTP client adapter using Req library.

  Implements HTTPClientBehaviour for dependency injection.
  """

  @behaviour GscAnalytics.DataSources.SERP.HTTPClientBehaviour

  @impl true
  def get(url, opts) do
    params = Keyword.get(opts, :params, %{})

    case Req.get(url, params: params) do
      {:ok, %{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
