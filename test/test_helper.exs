Mox.defmock(GscAnalytics.HTTPClientMock, for: GscAnalytics.HTTPClient)
Application.put_env(:gsc_analytics, :http_client, GscAnalytics.HTTPClientMock)

# SERP HTTP client mock for ScrapFly API testing
Mox.defmock(GscAnalytics.DataSources.SERP.HTTPClientMock,
  for: GscAnalytics.DataSources.SERP.HTTPClientBehaviour
)

Application.put_env(
  :gsc_analytics,
  :serp_http_client,
  GscAnalytics.DataSources.SERP.HTTPClientMock
)

ExUnit.start(exclude: [:performance])
Ecto.Adapters.SQL.Sandbox.mode(GscAnalytics.Repo, :manual)
