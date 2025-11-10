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
    {:ok, _view, html} = live(conn, ~p"/dashboard/#{property.id}/crawler")

    label =
      property.display_name ||
        AccountHelpers.display_property_label(property.property_url)

    assert html =~ "PROPERTY SELECTOR"
    assert html =~ label
  end

  describe "progress scoping" do
    test "updates progress when metadata matches current property", %{
      conn: conn,
      workspace: workspace,
      property: property
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard/#{property.id}/crawler")
      refute html =~ "SCAN PROGRESS"

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
      assert rendered =~ "SCAN PROGRESS"
      assert rendered =~ "0/5"
    end

    test "ignores progress from other properties", %{
      conn: conn,
      workspace: workspace,
      property: property
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard/#{property.id}/crawler")
      refute html =~ "SCAN PROGRESS"

      job =
        progress_job(%{
          metadata: %{
            account_id: workspace.id,
            property_id: "different-property"
          }
        })

      send(view.pid, {:crawler_progress, %{type: :started, job: job}})

      rendered = render(view)
      refute rendered =~ "SCAN PROGRESS"
    end
  end

  describe "redirect helpers" do
    alias GscAnalyticsWeb.DashboardCrawlerLive

    test "redirect_destination prefers redirect_url when present" do
      info = %{
        redirect_url: "https://example.com/target",
        http_redirect_chain: %{"step_1" => "https://example.com/old"}
      }

      assert DashboardCrawlerLive.redirect_destination(info) == "https://example.com/target"
    end

    test "redirect_destination falls back to last step in redirect chain" do
      info = %{
        redirect_url: "",
        http_redirect_chain: %{
          "step_1" => "https://example.com/a",
          "step_2" => "https://example.com/b"
        }
      }

      assert DashboardCrawlerLive.redirect_destination(info) == "https://example.com/b"
    end

    test "redirecting?/1 requires 3xx status and destination" do
      assert DashboardCrawlerLive.redirecting?(%{
               http_status: 302,
               redirect_url: "https://example.com/final"
             })

      refute DashboardCrawlerLive.redirecting?(%{
               http_status: 200,
               redirect_url: "https://example.com"
             })

      refute DashboardCrawlerLive.redirecting?(%{http_status: 301, redirect_url: nil})
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
