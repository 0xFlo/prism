defmodule GscAnalyticsWeb.Components.DashboardTablesTest do
  use GscAnalyticsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ecto.UUID
  alias GscAnalyticsWeb.Components.DashboardTables
  alias GscAnalyticsWeb.PropertyRoutes

  describe "url_breadcrumb/1" do
    test "renders the domain breadcrumb when url has no path" do
      property_id = UUID.generate()
      url = "https://sub.example.com"

      html =
        render_component(&DashboardTables.url_breadcrumb/1,
          url: url,
          property_id: property_id
        )

      expected_link = PropertyRoutes.url_path(property_id, %{url: url})

      assert html =~ "sub.example.com"
      assert html =~ ~s[href="#{expected_link}"]
      refute html =~ "..."
    end

    test "collapses middle segments when exceeding max_segments" do
      property_id = UUID.generate()
      url = "https://example.com/a/b/c/d"

      html =
        render_component(&DashboardTables.url_breadcrumb/1,
          url: url,
          property_id: property_id,
          max_segments: 2
        )

      assert html =~ "example.com"
      assert html =~ ">...</span>"
      assert html =~ ~s[title="d"]
      refute html =~ ~s[title="b"]
    end

    test "uses explicit link_to when provided" do
      property_id = UUID.generate()
      url = "https://example.com/hello"
      custom_path = "/custom/path"

      html =
        render_component(&DashboardTables.url_breadcrumb/1,
          url: url,
          property_id: property_id,
          link_to: custom_path
        )

      assert html =~ ~s[href="#{custom_path}"]
      assert html =~ "hello"
    end
  end

  describe "pagination/1" do
    test "shows range summary and disables prev/next appropriately" do
      html =
        render_component(&DashboardTables.pagination/1,
          current_page: 1,
          total_pages: 3,
          total_items: 120,
          per_page: 50,
          per_page_options: [25, 50, 100]
        )

      assert html =~ "Showing <span class=\"font-semibold text-slate-900\">1</span>"
      assert html =~ "text-slate-900\">50</span>"
      assert html =~ "120"
      assert html =~ ~s[phx-click="prev_page" disabled]
      refute html =~ ~s[phx-click="next_page" disabled]
      assert html =~ ~s[aria-label="Page 1" aria-current="page"]
      refute html =~ ~s[aria-label="Page 3" aria-current="page"]
    end
  end

  describe "backlinks_table/1" do
    test "renders empty state when there are no backlinks" do
      html =
        render_component(&DashboardTables.backlinks_table/1,
          backlinks: [],
          sort_by: "first_seen_at",
          sort_direction: "desc"
        )

      assert html =~ "No backlinks found for this URL."
    end
  end
end
