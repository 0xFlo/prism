defmodule GscAnalytics.Analysis.HighIntentContentTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.Analysis.HighIntentContent

  @high_intent_slug "alternatives-to-cloudscraper-to-bypass-cloudflare.md"
  @low_intent_slug "3-ways-to-install-python-requests-library.md"

  test "includes known bottom-funnel article" do
    posts = HighIntentContent.list_high_intent_posts()

    assert Enum.any?(posts, fn %{filename: filename} -> filename == @high_intent_slug end)
  end

  test "excludes purely educational tutorial" do
    posts = HighIntentContent.list_high_intent_posts()

    refute Enum.any?(posts, fn %{filename: filename} -> filename == @low_intent_slug end)
  end

  test "csv export escapes commas" do
    posts = [
      %{title: "Best Proxy Providers 2025", url: "https://example.com", filename: "best-proxies.md",
        score: 3, signals: ["best", "providers"]}
    ]

    assert HighIntentContent.to_csv(posts) ==
             "title,url,filename,score,signals\n\"Best Proxy Providers 2025\",https://example.com,best-proxies.md,3,\"best providers\"\n"
  end
end
