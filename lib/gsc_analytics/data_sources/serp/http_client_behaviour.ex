defmodule GscAnalytics.DataSources.SERP.HTTPClientBehaviour do
  @moduledoc """
  Behavior for HTTP clients used in SERP integration.

  This allows dependency injection for testing with Mox.
  """

  @callback get(url :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
