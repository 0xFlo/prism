defmodule GscAnalyticsWeb.AccountsRedirectController do
  use GscAnalyticsWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/users/settings#connections")
  end
end
