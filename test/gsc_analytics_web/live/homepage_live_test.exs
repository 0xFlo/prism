defmodule GscAnalyticsWeb.HomepageLiveTest do
  use GscAnalyticsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "unauthenticated visitors" do
    test "renders marketing experience", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Your AI SEO Agent"
      assert html =~ "Performance Trends"
    end
  end

  describe "authenticated users" do
    setup :register_and_log_in_user

    test "are redirected to the dashboard", %{conn: conn, property: property} do
      expected_path = "/dashboard/#{property.id}"
      assert {:error, {:live_redirect, %{to: ^expected_path}}} = live(conn, ~p"/")
    end
  end
end
