defmodule GscAnalyticsWeb.Components.DashboardFiltersTest do
  use GscAnalyticsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GscAnalyticsWeb.Components.DashboardFilters

  describe "filter_bar/1" do
    test "shows active filter count and clear button" do
      html =
        render_component(&DashboardFilters.filter_bar/1,
          filter_http_status: "ok",
          filter_clicks: "10+",
          filter_page_type: "blog",
          filter_position: nil,
          filter_ctr: nil,
          filter_backlinks: nil,
          filter_redirect: nil,
          filter_first_seen: nil
        )

      assert html =~ "Filters"
      assert html =~ "badge badge-primary"
      assert html =~ "Clear all filters"
      assert html =~ ~s[phx-change="filter_http_status"]
    end
  end

  describe "page_type_multiselect/1" do
    test "indicates when selections exist and allows clearing" do
      html =
        render_component(&DashboardFilters.page_type_multiselect/1,
          filter_page_type: "blog,product"
        )

      assert html =~ "2 selected"
      assert html =~ "Clear selection"
      assert html =~ ~s[phx-value-page_type=""]
    end
  end
end
