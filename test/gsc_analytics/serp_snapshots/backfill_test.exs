defmodule GscAnalytics.SerpSnapshots.BackfillTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.Schemas.SerpSnapshot
  alias GscAnalytics.SerpSnapshots.Backfill

  describe "run/1" do
    test "enriches legacy rows with competitors, content types, and ScrapFly flags" do
      snapshot =
        insert_snapshot(%{
          competitors: [],
          content_types_present: [],
          ai_overview_present: true,
          ai_overview_citations: [
            %{"domain" => "ScrapFly.io", "position" => 4}
          ],
          scrapfly_mentioned_in_ao: false,
          scrapfly_citation_position: nil
        })

      assert {:ok, stats} = Backfill.run()
      assert stats.updated == 1

      reloaded = Repo.get!(SerpSnapshot, snapshot.id)

      assert length(reloaded.competitors) == 10
      assert Enum.member?(reloaded.content_types_present, "reddit")
      assert Enum.member?(reloaded.content_types_present, "website")
      assert reloaded.scrapfly_mentioned_in_ao
      assert reloaded.scrapfly_citation_position == 4
    end

    test "dry run reports updates without mutating database" do
      snapshot =
        insert_snapshot(%{
          competitors: [],
          content_types_present: [],
          ai_overview_present: true,
          ai_overview_citations: [
            %{"domain" => "scrapfly.io", "position" => 2}
          ],
          scrapfly_mentioned_in_ao: false,
          scrapfly_citation_position: nil
        })

      assert {:ok, stats} = Backfill.run(dry_run: true)
      assert stats.updated == 1

      reloaded = Repo.get!(SerpSnapshot, snapshot.id)
      assert reloaded.competitors == []
      assert reloaded.content_types_present == []
      refute reloaded.scrapfly_mentioned_in_ao
      assert is_nil(reloaded.scrapfly_citation_position)
    end
  end

  defp insert_snapshot(attrs) do
    base_attrs = %{
      account_id: 1,
      property_url: "sc-domain:example.com",
      url: "https://scrapfly.io/blog/web-scraping",
      keyword: "web scraping",
      serp_features: [],
      geo: "us",
      raw_response: sample_raw_response(),
      checked_at: DateTime.utc_now()
    }

    %SerpSnapshot{}
    |> SerpSnapshot.changeset(Map.merge(base_attrs, attrs))
    |> Repo.insert!()
  end

  defp sample_raw_response do
    %{"result" => %{"content" => sample_html()}}
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
    <div class="g">
      <div class="yuRUbf">
        <a href="https://www.reddit.com/r/webscraping">
          <h3>Reddit thread about scraping</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(2) do
    """
    <div class="g">
      <div class="yuRUbf">
        <a href="https://www.youtube.com/watch?v=123">
          <h3>YouTube tutorial</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(3) do
    """
    <div class="g">
      <div class="yuRUbf">
        <a href="https://stackoverflow.com/questions/1">
          <h3>StackOverflow question</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(4) do
    """
    <div class="g">
      <div class="yuRUbf">
        <a href="https://scrapfly.io/blog/web-scraping">
          <h3>ScrapFly guide</h3>
        </a>
      </div>
    </div>
    """
  end

  defp result_block(index) do
    url = "https://example#{index}.com"

    """
    <div class="g">
      <div class="yuRUbf">
        <a href="#{url}">
          <h3>Generic result #{index}</h3>
        </a>
      </div>
    </div>
    """
  end
end
