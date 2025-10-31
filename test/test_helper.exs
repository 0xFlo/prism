Mox.defmock(GscAnalytics.HTTPClientMock, for: GscAnalytics.HTTPClient)
Application.put_env(:gsc_analytics, :http_client, GscAnalytics.HTTPClientMock)

ExUnit.start(exclude: [:performance])
Ecto.Adapters.SQL.Sandbox.mode(GscAnalytics.Repo, :manual)
