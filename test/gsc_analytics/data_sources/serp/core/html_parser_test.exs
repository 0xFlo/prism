defmodule GscAnalytics.DataSources.SERP.Core.HTMLParserTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.HTMLParser

  describe "classify_content_type/2" do
    test "detects reddit threads" do
      assert HTMLParser.classify_content_type("https://www.reddit.com/r/webscraping", "Thread") ==
               "reddit"
    end

    test "detects youtube videos" do
      assert HTMLParser.classify_content_type("https://youtu.be/123", "Video guide") ==
               "youtube"
    end

    test "falls back to website" do
      assert HTMLParser.classify_content_type("https://scrapfly.io/blog", "Guide") == "website"
    end
  end

  describe "extract_domain/1" do
    test "removes protocol and www" do
      assert HTMLParser.extract_domain("https://www.Example.com/path") == "example.com"
    end
  end

  describe "extract_competitors/1" do
    test "returns at most 10 normalized entries" do
      competitors = HTMLParser.extract_competitors(sample_html())

      assert length(competitors) == 10

      first = List.first(competitors)
      assert first.position == 1
      assert first.domain == "reddit.com"
      assert first.content_type == "reddit"
    end
  end

  describe "parse_serp_response/2" do
    test "populates content types and competitors" do
      response = %{"result" => %{"content" => sample_html()}}

      parsed = HTMLParser.parse_serp_response(response, "https://scrapfly.io/blog")

      assert parsed.position == 4
      assert Enum.any?(parsed.competitors, &(&1.domain == "scrapfly.io"))
      assert Enum.sort(parsed.content_types_present) == ["forum", "reddit", "website", "youtube"]
    end
  end

  defp sample_html do
    1..12
    |> Enum.map(&result_block/1)
    |> Enum.join("\n")
    |> then(fn body ->
      """
      <html>
        <body>
          #{body}
        </body>
      </html>
      """
    end)
  end

  defp result_block(1) do
    """
    <div class=\"g\">
      <div class=\"yuRUbf\">
        <a href=\"https://www.reddit.com/r/webscraping\">
          <h3>Reddit thread about scraping</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(2) do
    """
    <div class=\"g\">
      <div class=\"yuRUbf\">
        <a href=\"https://www.youtube.com/watch?v=123\">
          <h3>YouTube tutorial</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(3) do
    """
    <div class=\"g\">
      <div class=\"yuRUbf\">
        <a href=\"https://stackoverflow.com/questions/1\">
          <h3>StackOverflow question</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(4) do
    """
    <div class=\"g\">
      <div class=\"yuRUbf\">
        <a href=\"https://scrapfly.io/blog/web-scraping\">
          <h3>ScrapFly guide</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(index) do
    url = "https://example#{index}.com"

    """
    <div class=\"g\">
      <div class=\"yuRUbf\">
        <a href=\"#{url}\">
          <h3>Generic result #{index}</h3>
        </a>
      </div>
    </div>
    """
  end
end
