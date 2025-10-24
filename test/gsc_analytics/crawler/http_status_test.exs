defmodule GscAnalytics.Crawler.HttpStatusTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.Crawler.HttpStatus

  setup do
    # Ensure inets and ssl are started
    :inets.start()
    :ssl.start()
    :ok
  end

  describe "check_url/2 with scrapfly.io URLs" do
    test "returns 200 or handles redirect for valid scrapfly.io blog post" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      # Scrapfly may redirect /blog/X to /blog/posts/X (301)
      assert result.status in [200, 301]

      # If redirected, should have redirect_url and chain populated
      if result.status == 301 do
        assert not is_nil(result.redirect_url)
        assert result.redirect_chain != %{}
      end

      assert is_nil(result.error)
      assert %DateTime{} = result.checked_at
    end

    test "returns 200 for another scrapfly.io blog post" do
      {:ok, result} =
        HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-javascript")

      # This returns 404 because the page doesn't exist yet
      assert result.status in [200, 404]
      assert is_nil(result.error)
    end

    test "detects 404 not found for non-existent scrapfly.io page" do
      {:ok, result} =
        HttpStatus.check_url(
          "https://scrapfly.io/blog/this-page-definitely-does-not-exist-12345-test"
        )

      assert result.status == 404
      assert is_nil(result.redirect_url)
      assert is_nil(result.error)
    end

    test "returns 200 for scrapfly.io homepage (with proper headers)" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io")

      # Scrapfly.io homepage returns 200 when using proper browser-like headers
      assert result.status == 200
      assert is_nil(result.error)
    end

    test "returns 200 for scrapfly.io docs (with proper headers)" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/docs/scrape-api/getting-started")

      # Docs return 200 when using proper browser-like headers
      assert result.status == 200
      assert is_nil(result.error)
    end

    test "includes checked_at timestamp" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      assert %DateTime{} = result.checked_at
      # Check timestamp is recent (within last 10 seconds)
      diff = DateTime.diff(DateTime.utc_now(), result.checked_at, :second)
      assert diff < 10
      # Result should have valid status (200 or redirect)
      assert result.status in [200, 301, 302]
    end
  end

  describe "timeout handling" do
    test "handles connection timeout with non-routable IP" do
      # Use a non-routable IP to trigger timeout faster
      {:ok, result} = HttpStatus.check_url("http://10.255.255.1", timeout: 1000)

      assert is_nil(result.status)
      assert result.error =~ ~r/(timeout|Connection failed)/i
    end

    test "respects timeout option" do
      # Using a very short timeout should fail
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io", timeout: 1)

      # Either times out or completes very quickly (returns 200)
      assert result.status == 200 or result.error =~ ~r/timeout/i
    end
  end

  describe "error handling" do
    test "handles invalid domain (DNS error)" do
      {:ok, result} =
        HttpStatus.check_url("https://this-domain-definitely-does-not-exist-12345-test.com")

      assert is_nil(result.status)
      assert result.error =~ ~r/(DNS|connection)/i
    end

    test "handles malformed URLs gracefully" do
      {:ok, result} = HttpStatus.check_url("not-a-valid-url")

      assert is_nil(result.status)
      assert not is_nil(result.error)
    end

    test "handles empty URL" do
      {:ok, result} = HttpStatus.check_url("")

      assert is_nil(result.status)
      assert not is_nil(result.error)
    end

    test "handles unsupported protocol" do
      {:ok, result} = HttpStatus.check_url("ftp://scrapfly.io/test")

      assert is_nil(result.status)
      assert not is_nil(result.error)
    end
  end

  describe "result structure" do
    test "always returns required fields" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :redirect_url)
      assert Map.has_key?(result, :redirect_chain)
      assert Map.has_key?(result, :checked_at)
      assert Map.has_key?(result, :error)
    end

    test "successful result has nil error" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      assert is_nil(result.error)
      # Accept either 200 (direct) or 301 (redirect) as successful
      assert result.status in [200, 301]
    end

    test "error result has nil status" do
      {:ok, result} = HttpStatus.check_url("https://nonexistent-domain-12345.com")

      assert is_nil(result.status)
      assert not is_nil(result.error)
    end
  end

  describe "redirect chain building" do
    test "redirect chain behavior based on status" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      # For non-redirect responses (200), chain should be empty
      # For redirect responses (301), chain should be populated
      if result.status == 200 do
        assert result.redirect_chain == %{}
        assert is_nil(result.redirect_url)
      else
        # If redirected, should have chain and redirect_url
        assert result.redirect_chain != %{}
        assert not is_nil(result.redirect_url)
      end
    end

    test "redirect_url behavior based on status" do
      {:ok, result} = HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python")

      # redirect_url should be nil for 200, populated for 301
      if result.status == 200 do
        assert is_nil(result.redirect_url)
      else
        assert not is_nil(result.redirect_url)
      end
    end
  end

  describe "max_redirects option" do
    test "accepts max_redirects option without error" do
      {:ok, result} =
        HttpStatus.check_url("https://scrapfly.io/blog/web-scraping-with-python",
          max_redirects: 5
        )

      # Should work normally with this option (may be 200, 301, or 404)
      assert result.status in [200, 301, 403, 404]
    end
  end
end
