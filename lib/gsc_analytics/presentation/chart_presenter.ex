defmodule GscAnalytics.Presentation.ChartPresenter do
  @moduledoc """
  Builds chart-friendly redirect events for Content Insights visualisations.

  The presenter normalises redirect checkpoints into the correct time bucket
  (daily, weekly, monthly) and emits data-only maps that LiveViews can render
  without additional formatting logic.
  """

  @type raw_event :: %{
          optional(:source_url) => String.t() | nil,
          optional(:target_url) => String.t() | nil,
          optional(:status) => integer() | nil,
          checked_at: DateTime.t() | nil
        }

  @type presented_event :: %{
          date: String.t(),
          label: String.t(),
          tooltip: String.t() | nil
        }

  @doc """
  Convert redirect crawl events into chart annotations for the requested view mode.

  `view_mode` accepts "daily", "weekly", or "monthly". Events without a
  timestamp are ignored to keep the chart data clean.
  """
  @spec build_chart_events(String.t(), [raw_event()]) :: [presented_event()]
  def build_chart_events(_view_mode, []), do: []

  def build_chart_events(view_mode, events) when is_list(events) do
    events
    |> prefer_gsc_events()
    |> Enum.filter(&match?(%{checked_at: %DateTime{}}, &1))
    |> Enum.map(&present_event(&1, view_mode))
    |> Enum.group_by(& &1.date)
    |> Enum.flat_map(&collapse_group/1)
  end

  defp present_event(event, view_mode) do
    date =
      event.checked_at
      |> DateTime.to_date()
      |> normalize_event_date(view_mode)
      |> Date.to_string()

    %{
      date: date,
      label: format_event_label(event),
      tooltip: build_event_tooltip(event)
    }
  end

  defp collapse_group({date, [%{label: label, tooltip: tooltip}]}) do
    [%{date: date, label: label, tooltip: tooltip}]
  end

  defp collapse_group({date, events}) do
    tooltips =
      events
      |> Enum.map(& &1.tooltip)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    [
      %{
        date: date,
        label: "URL changes (#{length(events)})",
        tooltip: if(tooltips == "", do: nil, else: tooltips)
      }
    ]
  end

  defp normalize_event_date(date, "weekly") do
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  defp normalize_event_date(date, "monthly"), do: %{date | day: 1}
  defp normalize_event_date(date, _view_mode), do: date

  defp format_event_label(%{type: :gsc_migration} = event) do
    slug = extract_event_slug(event[:target_url])
    icon = confidence_icon(event[:confidence])
    destination = slug || event[:target_url] || "new URL"
    "#{icon} Traffic shift → #{destination}"
  end

  defp format_event_label(%{type: :http_redirect, status: status, target_url: target}) do
    slug = extract_event_slug(target)

    cond do
      status && slug -> "#{status} → #{slug}"
      status && !slug -> "#{status} redirect"
      !status && slug -> "→ #{slug}"
      true -> "URL change"
    end
  end

  defp format_event_label(event), do: format_event_label(Map.put(event, :type, :http_redirect))

  defp build_event_tooltip(%{type: :gsc_migration} = event) do
    [
      migration_path(event),
      date_line("New URL first impressions", event[:new_first_impression_on]),
      date_line("Old URL last seen", event[:old_last_seen_on]),
      confidence_line(event[:confidence])
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp build_event_tooltip(%{source_url: source, target_url: target}) do
    cond do
      source && target -> "#{source} → #{target}"
      target -> "Redirected to #{target}"
      true -> nil
    end
  end

  defp migration_path(%{source_url: source, target_url: target})
       when is_binary(source) and is_binary(target),
       do: "#{source} → #{target}"

  defp migration_path(_), do: nil

  defp date_line(_label, nil), do: nil
  defp date_line(label, %Date{} = date), do: "#{label}: #{Date.to_string(date)}"

  defp confidence_line(nil), do: nil

  defp confidence_line(confidence) do
    "Confidence: #{format_confidence(confidence)}"
  end

  defp format_confidence(confidence) do
    confidence
    |> to_string()
    |> String.upcase()
  end

  defp confidence_icon(:high), do: "📊✅"
  defp confidence_icon(:medium), do: "📊"
  defp confidence_icon(:low), do: "📊⚠️"
  defp confidence_icon(_), do: "📊"

  defp prefer_gsc_events(events) do
    gsc_events = Enum.filter(events, &match?(%{type: :gsc_migration}, &1))

    case gsc_events do
      [] -> events
      gsc -> gsc
    end
  end

  defp extract_event_slug(nil), do: nil

  defp extract_event_slug(url) do
    uri = URI.parse(url)

    cond do
      uri.path && uri.path != "" ->
        uri.path
        |> String.trim()
        |> String.trim_trailing("/")
        |> case do
          "" -> slug_from_host(uri)
          path -> truncate_string(path, 32)
        end

      true ->
        slug_from_host(uri)
    end
  end

  defp slug_from_host(%URI{host: host}) when is_binary(host), do: host
  defp slug_from_host(_), do: nil

  defp truncate_string(string, max_length) when byte_size(string) <= max_length, do: string

  defp truncate_string(string, max_length) do
    string
    |> String.slice(0, max_length)
    |> Kernel.<>("…")
  end
end
