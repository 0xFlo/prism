defmodule GscAnalyticsWeb.Live.ChartHelpers do
  @moduledoc """
  Shared chart helpers for LiveView dashboards.

  Provides consistent chart series toggle behavior across all dashboard views.
  Eliminates code duplication and ensures consistent series visibility logic.

  ## Usage

      defmodule MyDashboardLive do
        use GscAnalyticsWeb, :live_view
        import GscAnalyticsWeb.Live.ChartHelpers

        def handle_event("toggle_series", %{"metric" => metric_str}, socket) do
          new_series = toggle_chart_series(metric_str, socket.assigns.visible_series)
          # Handle URL update or socket assign based on your LiveView's needs
        end
      end
  """

  @valid_metrics [:clicks, :impressions, :ctr, :position]

  @doc """
  Toggle a metric's visibility in the chart series list.

  Returns the updated series list with the metric either added or removed.
  Enforces that at least one series is always visible - if removing the last
  series, it stays visible.

  ## Parameters

    - `metric_str` - String representation of the metric (e.g., "clicks")
    - `current_series` - List of currently visible metric atoms

  ## Examples

      iex> toggle_chart_series("clicks", [:impressions])
      [:clicks, :impressions]

      iex> toggle_chart_series("clicks", [:clicks, :impressions])
      [:impressions]

      iex> toggle_chart_series("clicks", [:clicks])
      [:clicks]  # Can't remove last series

      iex> toggle_chart_series("invalid", [:clicks])
      [:clicks]  # Invalid metric is ignored
  """
  @spec toggle_chart_series(String.t(), [atom()]) :: [atom()]
  def toggle_chart_series(metric_str, current_series) when is_binary(metric_str) do
    case safe_to_metric_atom(metric_str) do
      {:ok, metric} ->
        do_toggle_series(metric, current_series)

      :error ->
        # Invalid metric string, return current series unchanged
        current_series
    end
  end

  @doc """
  Check if a metric atom is a valid chart series.

  ## Examples

      iex> valid_metric?(:clicks)
      true

      iex> valid_metric?(:invalid)
      false
  """
  @spec valid_metric?(atom()) :: boolean()
  def valid_metric?(metric) when is_atom(metric) do
    metric in @valid_metrics
  end

  @doc """
  Get the list of all valid chart metrics.

  ## Examples

      iex> valid_metrics()
      [:clicks, :impressions, :ctr, :position]
  """
  @spec valid_metrics() :: [atom()]
  def valid_metrics, do: @valid_metrics

  # Private helpers

  defp safe_to_metric_atom(metric_str) do
    try do
      metric = String.to_existing_atom(metric_str)

      if valid_metric?(metric) do
        {:ok, metric}
      else
        :error
      end
    rescue
      ArgumentError -> :error
    end
  end

  defp do_toggle_series(metric, current_series) do
    new_series =
      if metric in current_series do
        List.delete(current_series, metric)
      else
        [metric | current_series]
      end

    # Enforce at least one series visible
    if Enum.empty?(new_series), do: [metric], else: new_series
  end
end
