defmodule GscAnalytics.Presentation.ChartPresenterTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.Presentation.ChartPresenter

  describe "build_chart_events/2" do
    test "builds events for daily view" do
      events = [
        %{
          checked_at: ~U[2025-01-15 12:00:00Z],
          status: 301,
          source_url: "https://example.com/old",
          target_url: "https://example.com/new"
        }
      ]

      assert [event] = ChartPresenter.build_chart_events("daily", events)
      assert event.date == "2025-01-15"
      assert event.label == "301 → /new"
      assert event.tooltip == "https://example.com/old → https://example.com/new"
    end

    test "normalizes weekly events to the week start" do
      events = [
        %{
          checked_at: ~U[2025-01-15 12:00:00Z],
          status: 302,
          source_url: "https://example.com/a",
          target_url: "https://example.com/b"
        }
      ]

      assert [%{date: date}] = ChartPresenter.build_chart_events("weekly", events)
      assert date == "2025-01-13"
    end

    test "normalizes monthly events to the first of month" do
      events = [
        %{
          checked_at: ~U[2025-01-31 08:00:00Z],
          status: 301,
          source_url: "https://example.com/x",
          target_url: "https://example.com/y"
        }
      ]

      assert [%{date: "2025-01-01"}] = ChartPresenter.build_chart_events("monthly", events)
    end

    test "groups multiple events on the same day" do
      events = [
        %{
          checked_at: ~U[2025-01-15 08:00:00Z],
          status: 301,
          source_url: "https://example.com/one",
          target_url: "https://example.com/two"
        },
        %{
          checked_at: ~U[2025-01-15 14:00:00Z],
          status: 302,
          source_url: "https://example.com/alpha",
          target_url: "https://example.com/beta"
        }
      ]

      assert [event] = ChartPresenter.build_chart_events("daily", events)
      assert event.label == "URL changes (2)"
      assert event.tooltip =~ "https://example.com/one"
      assert event.tooltip =~ "https://example.com/alpha"
    end

    test "ignores events without timestamps" do
      events = [
        %{
          checked_at: nil,
          status: 301,
          source_url: "https://example.com/ghost",
          target_url: "https://example.com/live"
        }
      ]

      assert [] == ChartPresenter.build_chart_events("daily", events)
    end

    test "builds migration events with confidence details" do
      events = [
        %{
          type: :gsc_migration,
          checked_at: ~U[2025-02-01 00:00:00Z],
          source_url: "https://example.com/old",
          target_url: "https://example.com/new",
          confidence: :high,
          new_first_impression_on: ~D[2025-02-01],
          old_last_seen_on: ~D[2025-01-31]
        }
      ]

      assert [event] = ChartPresenter.build_chart_events("daily", events)
      assert event.label == "📊✅ Traffic shift → /new"
      assert event.tooltip =~ "New URL first impressions: 2025-02-01"
      assert event.tooltip =~ "Old URL last seen: 2025-01-31"
      assert event.tooltip =~ "Confidence: HIGH"
    end

    test "prefers gsc events when both types exist" do
      events = [
        %{
          type: :http_redirect,
          checked_at: ~U[2025-02-10 00:00:00Z],
          status: 301,
          source_url: "https://example.com/old",
          target_url: "https://example.com/new"
        },
        %{
          type: :gsc_migration,
          checked_at: ~U[2025-02-01 00:00:00Z],
          source_url: "https://example.com/old",
          target_url: "https://example.com/new",
          confidence: :high,
          new_first_impression_on: ~D[2025-02-01],
          old_last_seen_on: ~D[2025-01-31]
        }
      ]

      assert [event] = ChartPresenter.build_chart_events("daily", events)
      assert event.date == "2025-02-01"
      assert String.starts_with?(event.label, "📊✅")
    end
  end
end
