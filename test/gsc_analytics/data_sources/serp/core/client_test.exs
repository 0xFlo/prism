defmodule GscAnalytics.DataSources.SERP.Core.ClientTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.Client

  @moduletag :tdd

  describe "build_search_url/2" do
    test "constructs valid Google search URL" do
      url = Client.build_search_url("test query", "us")
      assert url =~ "https://www.google.com/search"
      assert url =~ "q=test"
      assert url =~ "query"
      assert url =~ "gl=us"
      assert url =~ "hl=en"
    end

    test "URL encodes special characters in keyword" do
      url = Client.build_search_url("elixir & phoenix framework", "us")
      assert url =~ "elixir"
      assert url =~ "phoenix"
      assert url =~ "framework"
      # & should be URL encoded as %26 in the query value
      assert url =~ "%26"
    end

    test "respects different geo parameters" do
      url_us = Client.build_search_url("test", "us")
      url_uk = Client.build_search_url("test", "uk")

      assert url_us =~ "gl=us"
      assert url_uk =~ "gl=uk"
    end
  end

  describe "scrape_google/2" do
    @tag :external
    test "makes successful API call to ScrapFly with real API" do
      # This test requires SCRAPFLY_API_KEY to be set
      # It will be skipped in CI unless explicitly enabled
      if System.get_env("SCRAPFLY_API_KEY") do
        assert {:ok, response} = Client.scrape_google("elixir programming")
        assert is_map(response)
      else
        # Skip if API key not available
        :ok
      end
    end

    test "builds request with required parameters" do
      # We can't easily mock Req without additional dependencies,
      # so we'll test the internal build_params function instead
      params = Client.build_params("test query", "us")

      assert is_map(params)
      assert params["url"] =~ "google.com/search"
      assert params["url"] =~ "test"
      assert params["country"] == "us"
      assert params["format"] == "json"
      assert params["render_js"] == "true"
      assert params["asp"] == "true"
    end

    test "uses default geo when not specified" do
      params = Client.build_params("test", nil)
      assert params["country"] == "us"
    end

    test "accepts custom geo parameter" do
      params = Client.build_params("test", "uk")
      assert params["country"] == "uk"
    end

    test "includes API key in params" do
      params = Client.build_params("test", "us")
      assert Map.has_key?(params, "key")
      assert is_binary(params["key"])
    end
  end

  describe "calculate_backoff_delay/1" do
    test "returns exponentially increasing delays" do
      assert Client.calculate_backoff_delay(0) == 1000
      assert Client.calculate_backoff_delay(1) == 2000
      assert Client.calculate_backoff_delay(2) == 4000
      assert Client.calculate_backoff_delay(3) == 8000
    end
  end
end
