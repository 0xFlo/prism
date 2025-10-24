defmodule GscAnalyticsWeb.PageController do
  use GscAnalyticsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
