defmodule GscAnalyticsWeb.DashboardCrawlerLiveTest do
  use GscAnalyticsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import GscAnalytics.WorkspaceTestHelper

  alias GscAnalyticsWeb.Live.AccountHelpers

  setup :register_and_log_in_user

  setup %{user: user} do
    {workspace, property} = setup_workspace_with_property(user: user)
    %{workspace: workspace, property: property}
  end

  test "renders property selector in hero section", %{conn: conn, property: property} do
    {:ok, _view, html} = live(conn, ~p"/dashboard/crawler")

    label =
      property.display_name ||
        AccountHelpers.display_property_label(property.property_url)

    assert html =~ "Property switcher"
    assert html =~ label
  end

  describe "progress scoping" do
    test "updates progress when metadata matches current property", %{
      conn: conn,
      workspace: workspace,
      property: property
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard/crawler")
      assert html =~ "No check in progress"

      job =
        progress_job(%{
          total_urls: 5,
          metadata: %{
            account_id: workspace.id,
            property_id: property.id,
            property_url: property.property_url,
            property_label: property.display_name || property.property_url
          }
        })

      send(view.pid, {:crawler_progress, %{type: :started, job: job}})

      rendered = render(view)
      assert rendered =~ "In Progress"
      assert rendered =~ "Checking 0/5 URLs"
    end

    test "ignores progress from other properties", %{conn: conn, workspace: workspace} do
      {:ok, view, html} = live(conn, ~p"/dashboard/crawler")
      assert html =~ "No check in progress"

      job =
        progress_job(%{
          metadata: %{
            account_id: workspace.id,
            property_id: "different-property"
          }
        })

      send(view.pid, {:crawler_progress, %{type: :started, job: job}})

      rendered = render(view)
      assert rendered =~ "No check in progress"
      refute rendered =~ "In Progress"
    end
  end

  defp progress_job(overrides) do
    base = %{
      id: "test-job",
      started_at: DateTime.utc_now(),
      finished_at: nil,
      total_urls: 10,
      checked: 0,
      duration_ms: nil,
      status_counts: %{
        "2xx" => 0,
        "3xx" => 0,
        "4xx" => 0,
        "5xx" => 0,
        "errors" => 0
      },
      metadata: %{}
    }

    Map.merge(base, overrides)
  end
end
