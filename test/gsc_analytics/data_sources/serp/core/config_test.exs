defmodule GscAnalytics.DataSources.SERP.Core.ConfigTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.Config

  describe "api_key/0" do
    test "returns configured API key when set" do
      # In test environment, returns placeholder value to avoid requiring real API key
      # In production, requires actual SCRAPFLY_API_KEY environment variable
      assert is_binary(Config.api_key())
      assert String.length(Config.api_key()) > 0
    end
  end

  test "base_url/0 returns ScrapFly API URL" do
    assert Config.base_url() == "https://api.scrapfly.io"
  end

  test "default_geo/0 returns US" do
    assert Config.default_geo() == "us"
  end

  test "default_format/0 returns json" do
    assert Config.default_format() == "json"
  end

  test "rate_limit_per_minute/0 returns 60" do
    assert Config.rate_limit_per_minute() == 60
  end

  test "unique_period_hours/0 returns 1" do
    assert Config.unique_period_hours() == 1
  end
end
