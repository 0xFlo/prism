defmodule GscAnalyticsWeb.Router do
  use GscAnalyticsWeb, :router

  import GscAnalyticsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GscAnalyticsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :oauth_rate_limited do
    plug GscAnalyticsWeb.Plugs.OAuthRateLimit
  end

  # Other scopes may use custom stacks.
  # scope "/api", GscAnalyticsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:gsc_analytics, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: GscAnalyticsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", GscAnalyticsWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{GscAnalyticsWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/dashboard/keywords", DashboardKeywordsLive, :index
      live "/dashboard/sync", DashboardSyncLive, :index
      live "/dashboard/crawler", DashboardCrawlerLive, :index
      live "/dashboard/workflows", DashboardWorkflowsLive, :index
      live "/dashboard/workflows/:id/edit", DashboardWorkflowBuilderLive, :edit
      live "/dashboard/url", DashboardUrlLive, :show
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    get "/accounts", AccountsRedirectController, :index

    scope "/auth/google" do
      pipe_through [:oauth_rate_limited]

      get "/", GoogleAuthController, :request
      get "/callback", GoogleAuthController, :callback
    end

    get "/dashboard/export", Dashboard.ExportController, :export_csv
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", GscAnalyticsWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{GscAnalyticsWeb.UserAuth, :mount_current_scope}] do
      live "/", HomepageLive, :index
      live "/pricing", PricingLive, :index
      live "/pricing/enterprise", PricingEnterpriseLive, :index
      live "/alternative/airops", AiropsAlternativeLive, :index
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", GscAnalyticsWeb do
    pipe_through [:api]

    get "/health", HealthController, :show
    get "/health/sync", HealthController, :sync
  end
end
