defmodule GscAnalyticsWeb.PageControllerTest do
  use GscAnalyticsWeb.ConnCase

  setup :register_and_log_in_user

  test "GET / redirects authenticated users with properties to dashboard", %{
    conn: conn,
    property: property
  } do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/dashboard/#{property.id}"
  end
end
