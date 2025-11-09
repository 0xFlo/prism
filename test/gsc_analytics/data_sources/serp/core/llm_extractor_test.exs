defmodule GscAnalytics.DataSources.SERP.Core.LLMExtractorTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.DataSources.SERP.Core.LLMExtractor

  @moduletag :tdd

  describe "build_extraction_prompt/1" do
    test "creates natural language prompt for SERP extraction" do
      url = "https://example.com"

      prompt = LLMExtractor.build_extraction_prompt(url)

      assert is_binary(prompt)
      assert prompt =~ "Extract"
      assert prompt =~ "position"
      assert prompt =~ url
      assert prompt =~ "JSON"
      assert prompt =~ "competing URLs"
      assert prompt =~ "SERP features"
    end

    test "includes instructions for position extraction" do
      url = "https://test.com/page"
      prompt = LLMExtractor.build_extraction_prompt(url)

      assert prompt =~ "1-100"
      assert prompt =~ "organic results"
    end

    test "specifies JSON format requirements" do
      prompt = LLMExtractor.build_extraction_prompt("https://example.com")

      assert prompt =~ "VALID JSON" or prompt =~ "valid JSON"
      assert prompt =~ "competitors"
      assert prompt =~ "serp_features"
    end

    test "instructs to return null if URL not found" do
      prompt = LLMExtractor.build_extraction_prompt("https://example.com")

      assert prompt =~ "null" or prompt =~ "not found"
    end
  end

  describe "parse_llm_response/2" do
    test "extracts position from LLM JSON response" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "content_type" => "application/json",
            "data" => %{
              "position" => 3,
              "competitors" => [
                %{"position" => 1, "url" => "https://competitor1.com", "title" => "Title 1"},
                %{"position" => 2, "url" => "https://competitor2.com", "title" => "Title 2"}
              ],
              "serp_features" => ["featured_snippet"]
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert result.position == 3
      assert is_list(result.competitors)
      assert length(result.competitors) == 2
      assert hd(result.competitors)["position"] == 1
      assert hd(result.competitors)["url"] == "https://competitor1.com"
      assert "featured_snippet" in result.serp_features
      assert %DateTime{} = result.parsed_at
    end

    test "returns nil position when URL not found" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => nil,
              "message" => "URL not found in search results"
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://notfound.com")

      assert is_nil(result.position)
      assert result.competitors == []
      assert result.serp_features == []
    end

    test "handles malformed LLM response gracefully" do
      llm_response = %{"result" => %{}}

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert is_nil(result.position)
      assert result.competitors == []
      assert result.serp_features == []
      assert Map.has_key?(result, :error)
    end

    test "handles missing result.extracted_data path" do
      llm_response = %{
        "result" => %{
          "status" => "DONE",
          "status_code" => 200
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert is_nil(result.position)
      assert is_binary(result.error)
    end

    test "handles empty competitors array" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => 1,
              "competitors" => [],
              "serp_features" => []
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert result.position == 1
      assert result.competitors == []
    end

    test "handles missing optional fields" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => 5
              # competitors and serp_features missing
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert result.position == 5
      assert result.competitors == []
      assert result.serp_features == []
    end

    test "extracts all SERP features" do
      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => 2,
              "competitors" => [],
              "serp_features" => [
                "featured_snippet",
                "people_also_ask",
                "local_pack",
                "video_carousel",
                "image_pack"
              ]
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      assert length(result.serp_features) == 5
      assert "featured_snippet" in result.serp_features
      assert "people_also_ask" in result.serp_features
      assert "local_pack" in result.serp_features
    end

    test "preserves competitor structure" do
      competitor = %{
        "position" => 1,
        "url" => "https://top-result.com",
        "title" => "The Best Result"
      }

      llm_response = %{
        "result" => %{
          "extracted_data" => %{
            "data" => %{
              "position" => 2,
              "competitors" => [competitor],
              "serp_features" => []
            }
          }
        }
      }

      result = LLMExtractor.parse_llm_response(llm_response, "https://example.com")

      [first_competitor] = result.competitors
      assert first_competitor["position"] == 1
      assert first_competitor["url"] == "https://top-result.com"
      assert first_competitor["title"] == "The Best Result"
    end
  end
end
