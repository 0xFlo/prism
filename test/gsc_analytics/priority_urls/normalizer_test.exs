defmodule GscAnalytics.PriorityUrls.NormalizerTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.PriorityUrls.Normalizer

  test "lowercases hostname and scheme" do
    assert Normalizer.normalize_url("HTTPS://Example.COM/path") == "https://example.com/path"
  end

  test "trims trailing slash for non-root paths" do
    assert Normalizer.normalize_url("https://example.com/path/") == "https://example.com/path"
  end

  test "preserves root slash" do
    assert Normalizer.normalize_url("https://example.com") == "https://example.com/"
  end

  test "preserves query parameters and fragments" do
    assert Normalizer.normalize_url("https://example.com/path/?b=2&a=1#section") ==
             "https://example.com/path?b=2&a=1#section"
  end
end
