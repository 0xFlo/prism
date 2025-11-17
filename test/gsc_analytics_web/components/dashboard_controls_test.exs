defmodule GscAnalyticsWeb.Components.DashboardControlsTest do
  use GscAnalyticsWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GscAnalyticsWeb.Components.DashboardControls

  describe "property_selector/1" do
    test "renders empty message when there are no options" do
      html =
        render_component(&DashboardControls.property_selector/1,
          property_options: [],
          property_label: nil,
          empty_message: "Pick something"
        )

      assert html =~ "Pick something"
      refute html =~ "phx-value-property_id"
    end

    test "renders available properties excluding the current one" do
      html =
        render_component(&DashboardControls.property_selector/1,
          property_options: [
            %{label: "Primary", id: "prop-1", favicon_url: nil},
            %{label: "Secondary", id: "prop-2", favicon_url: "https://example.com/favicon.ico"}
          ],
          property_label: "Primary",
          current_property_id: "prop-1"
        )

      assert html =~ "Primary"
      assert html =~ ~s[phx-value-property_id="prop-2"]
      assert html =~ "Secondary"
      refute html =~ ~s[phx-value-property_id="prop-1"]
    end
  end

  describe "interactive_metric_card/1" do
    test "emits toggle metadata when interactive" do
      html =
        render_component(&DashboardControls.interactive_metric_card/1,
          metric: :clicks,
          value: 1234,
          label: "Clicks",
          subtitle: "Last 7 days",
          active: true
        )

      assert html =~ ~s[phx-value-metric="clicks"]
      assert html =~ ~s[aria-pressed="true"]
      assert html =~ "1,234"
    end
  end
end
