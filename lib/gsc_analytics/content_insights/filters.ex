defmodule GscAnalytics.ContentInsights.Filters do
  @moduledoc """
  Composable filter functions for URL performance queries.

  This module provides a fluent API for building complex URL filters.
  Each function takes a query and returns a filtered query, allowing for
  easy composition via the pipe operator.

  ## Usage

      Performance
      |> for_account(account_id)
      |> for_property(property_url)
      |> Filters.apply_http_status("broken")
      |> Filters.apply_position_range("poor")
      |> Filters.apply_clicks_threshold("100+")
      |> Repo.all()

  ## Filter Categories

  - **HTTP Status**: Filter by response codes (200, 3xx, 4xx, 5xx)
  - **Performance Metrics**: CTR, position, clicks thresholds
  - **Content Status**: Update needed, priority levels
  - **Backlinks**: Count thresholds
  - **Dates**: First seen, last checked

  All filter functions safely handle nil values (no-op) and invalid inputs.
  """

  import Ecto.Query

  # ============================================================================
  # HTTP STATUS FILTERS
  # ============================================================================

  @doc """
  Filter URLs by HTTP status code ranges.

  ## Options
  - `nil` - No filter (returns all)
  - `"ok"` - Only 200 OK responses
  - `"redirect"` - Only 3xx redirects
  - `"broken"` - Only 4xx/5xx errors
  - `"unchecked"` - Only URLs never checked (http_status IS NULL)

  ## Examples

      query
      |> apply_http_status("broken")
      # WHERE http_status >= 400

      query
      |> apply_http_status("ok")
      # WHERE http_status = 200
  """
  def apply_http_status(query, nil), do: query
  def apply_http_status(query, ""), do: query

  def apply_http_status(query, "ok") do
    where(query, [_ls, _pm, _bl, p], p.http_status == 200)
  end

  def apply_http_status(query, "redirect") do
    where(query, [_ls, _pm, _bl, p], p.http_status >= 300 and p.http_status < 400)
  end

  def apply_http_status(query, "broken") do
    where(query, [_ls, _pm, _bl, p], p.http_status >= 400)
  end

  def apply_http_status(query, "unchecked") do
    where(query, [_ls, _pm, _bl, p], is_nil(p.http_status))
  end

  # Invalid input - return unfiltered
  def apply_http_status(query, _invalid), do: query

  # ============================================================================
  # POSITION FILTERS
  # ============================================================================

  @doc """
  Filter URLs by average search position ranges.

  ## Options
  - `nil` - No filter
  - `"top3"` - Positions 1-3 (podium positions)
  - `"top10"` - Positions 1-10 (first page)
  - `"page1"` - Positions 1-10 (alias for top10)
  - `"page2"` - Positions 11-20
  - `"poor"` - Position > 20 (poorly ranked)
  - `"unranked"` - Position = 0 or NULL

  ## Examples

      query
      |> apply_position_range("top10")
      # WHERE avg_position BETWEEN 1 AND 10

      query
      |> apply_position_range("poor")
      # WHERE avg_position > 20
  """
  def apply_position_range(query, nil), do: query
  def apply_position_range(query, ""), do: query

  def apply_position_range(query, "top3") do
    where(query, [ls], ls.avg_position >= 1.0 and ls.avg_position <= 3.0)
  end

  def apply_position_range(query, filter) when filter in ["top10", "page1"] do
    where(query, [ls], ls.avg_position >= 1.0 and ls.avg_position <= 10.0)
  end

  def apply_position_range(query, "page2") do
    where(query, [ls], ls.avg_position >= 11.0 and ls.avg_position <= 20.0)
  end

  def apply_position_range(query, "poor") do
    where(query, [ls], ls.avg_position > 20.0)
  end

  def apply_position_range(query, "unranked") do
    where(query, [ls], ls.avg_position == 0.0 or is_nil(ls.avg_position))
  end

  def apply_position_range(query, _invalid), do: query

  # ============================================================================
  # CLICKS THRESHOLD FILTERS
  # ============================================================================

  @doc """
  Filter URLs by minimum clicks threshold.

  ## Options
  - `nil` - No filter
  - `"10+"` - At least 10 clicks
  - `"100+"` - At least 100 clicks
  - `"1000+"` - At least 1000 clicks (high performers)
  - `"none"` - Zero clicks (impressions only)

  ## Examples

      query
      |> apply_clicks_threshold("100+")
      # WHERE lifetime_clicks >= 100

      query
      |> apply_clicks_threshold("none")
      # WHERE lifetime_clicks = 0
  """
  def apply_clicks_threshold(query, nil), do: query
  def apply_clicks_threshold(query, ""), do: query

  def apply_clicks_threshold(query, "10+") do
    where(query, [ls], ls.lifetime_clicks >= 10)
  end

  def apply_clicks_threshold(query, "100+") do
    where(query, [ls], ls.lifetime_clicks >= 100)
  end

  def apply_clicks_threshold(query, "1000+") do
    where(query, [ls], ls.lifetime_clicks >= 1000)
  end

  def apply_clicks_threshold(query, "none") do
    where(query, [ls], ls.lifetime_clicks == 0)
  end

  def apply_clicks_threshold(query, _invalid), do: query

  # ============================================================================
  # CTR FILTERS
  # ============================================================================

  @doc """
  Filter URLs by CTR (Click-Through Rate) ranges.

  ## Options
  - `nil` - No filter
  - `"high"` - CTR > 5% (excellent performance)
  - `"good"` - CTR between 3-5%
  - `"average"` - CTR between 1-3%
  - `"low"` - CTR < 1% (optimization opportunity)

  ## Examples

      query
      |> apply_ctr_range("low")
      # WHERE avg_ctr < 0.01 AND lifetime_impressions >= 100
      # (Only shows low CTR with significant impressions)
  """
  def apply_ctr_range(query, nil), do: query
  def apply_ctr_range(query, ""), do: query

  def apply_ctr_range(query, "high") do
    where(query, [ls], ls.avg_ctr > 0.05)
  end

  def apply_ctr_range(query, "good") do
    where(query, [ls], ls.avg_ctr > 0.03 and ls.avg_ctr <= 0.05)
  end

  def apply_ctr_range(query, "average") do
    where(query, [ls], ls.avg_ctr > 0.01 and ls.avg_ctr <= 0.03)
  end

  def apply_ctr_range(query, "low") do
    # Only show low CTR URLs with significant impressions (optimization candidates)
    where(query, [ls], ls.avg_ctr <= 0.01 and ls.lifetime_impressions >= 100)
  end

  def apply_ctr_range(query, _invalid), do: query

  # ============================================================================
  # BACKLINK FILTERS
  # ============================================================================

  @doc """
  Filter URLs by backlink count.

  ## Options
  - `nil` - No filter
  - `"any"` - Has at least 1 backlink
  - `"none"` - Zero backlinks
  - `"10+"` - At least 10 backlinks
  - `"100+"` - At least 100 backlinks (authority pages)

  ## Examples

      query
      |> apply_backlink_count("any")
      # WHERE backlink_count > 0

      query
      |> apply_backlink_count("none")
      # WHERE backlink_count = 0 OR backlink_count IS NULL
  """
  def apply_backlink_count(query, nil), do: query
  def apply_backlink_count(query, ""), do: query

  def apply_backlink_count(query, "any") do
    where(query, [_ls, _pm, bl], bl.backlink_count > 0)
  end

  def apply_backlink_count(query, "none") do
    where(query, [_ls, _pm, bl], is_nil(bl.backlink_count) or bl.backlink_count == 0)
  end

  def apply_backlink_count(query, "10+") do
    where(query, [_ls, _pm, bl], bl.backlink_count >= 10)
  end

  def apply_backlink_count(query, "100+") do
    where(query, [_ls, _pm, bl], bl.backlink_count >= 100)
  end

  def apply_backlink_count(query, _invalid), do: query

  # ============================================================================
  # DATE FILTERS
  # ============================================================================

  @doc """
  Filter URLs by first seen date (when they appeared in GSC).

  ## Options
  - `nil` - No filter
  - `Date` struct - URLs first seen after this date
  - `"7d"` - URLs discovered in last 7 days
  - `"30d"` - URLs discovered in last 30 days
  - `"90d"` - URLs discovered in last 90 days

  ## Examples

      query
      |> apply_first_seen_after(~D[2024-01-01])
      # WHERE first_seen_date >= '2024-01-01'

      query
      |> apply_first_seen_after("30d")
      # WHERE first_seen_date >= (CURRENT_DATE - INTERVAL '30 days')
  """
  def apply_first_seen_after(query, nil), do: query
  def apply_first_seen_after(query, ""), do: query

  def apply_first_seen_after(query, %Date{} = date) do
    where(query, [ls], ls.first_seen_date >= ^date)
  end

  def apply_first_seen_after(query, "7d") do
    cutoff = Date.add(Date.utc_today(), -7)
    where(query, [ls], ls.first_seen_date >= ^cutoff)
  end

  def apply_first_seen_after(query, "30d") do
    cutoff = Date.add(Date.utc_today(), -30)
    where(query, [ls], ls.first_seen_date >= ^cutoff)
  end

  def apply_first_seen_after(query, "90d") do
    cutoff = Date.add(Date.utc_today(), -90)
    where(query, [ls], ls.first_seen_date >= ^cutoff)
  end

  def apply_first_seen_after(query, _invalid), do: query

  @doc """
  Filter URLs by redirect status.

  ## Options
  - `nil` - No filter
  - `"yes"` - Has redirect (redirect_url is not null)
  - `"no"` - No redirect

  ## Examples

      query
      |> apply_has_redirect("yes")
      # WHERE redirect_url IS NOT NULL
  """
  def apply_has_redirect(query, nil), do: query
  def apply_has_redirect(query, ""), do: query

  def apply_has_redirect(query, "yes") do
    where(query, [_ls, _pm, _bl, p], not is_nil(p.redirect_url))
  end

  def apply_has_redirect(query, "no") do
    where(query, [_ls, _pm, _bl, p], is_nil(p.redirect_url))
  end

  def apply_has_redirect(query, _invalid), do: query

  # ============================================================================
  # COMBINED FILTERS (Smart Presets)
  # ============================================================================

  @doc """
  Apply "Quick Win Opportunities" filter - low-hanging fruit for SEO improvements.

  Criteria:
  - Position 11-30 (close to first page)
  - Impressions >= 100 (gets visibility)
  - CTR < 3% (room for improvement)
  - HTTP Status = 200 (not broken)

  These are URLs that with small optimizations could jump to page 1.
  """
  def apply_quick_wins(query) do
    query
    |> where(
      [ls, _pm, _bl, p],
      ls.avg_position > 10.0 and ls.avg_position <= 30.0 and
        ls.lifetime_impressions >= 100 and
        ls.avg_ctr < 0.03 and
        p.http_status == 200
    )
  end

  @doc """
  Apply "Broken High Performers" filter - important pages that are broken.

  Criteria:
  - Clicks >= 100 OR Backlinks >= 10 (was/is important)
  - HTTP Status >= 400 (broken)

  These need immediate attention as they're losing traffic.
  """
  def apply_broken_high_performers(query) do
    query
    |> where(
      [ls, _pm, bl, p],
      (ls.lifetime_clicks >= 100 or bl.backlink_count >= 10) and
        p.http_status >= 400
    )
  end

  @doc """
  Apply "Content Refresh Candidates" filter - old pages with declining performance.

  Criteria:
  - First seen > 365 days ago (old content)
  - Position > 20 (poorly ranked)
  - Clicks > 0 (has some traffic)

  These pages might benefit from content updates.
  """
  def apply_content_refresh_candidates(query) do
    cutoff = Date.add(Date.utc_today(), -365)

    query
    |> where(
      [ls],
      ls.first_seen_date < ^cutoff and
        ls.avg_position > 20.0 and
        ls.lifetime_clicks > 0
    )
  end
end
