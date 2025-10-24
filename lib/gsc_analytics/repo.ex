defmodule GscAnalytics.Repo do
  use Ecto.Repo,
    otp_app: :gsc_analytics,
    adapter: Ecto.Adapters.Postgres
end
