defmodule GscAnalytics.PriorityUrls.ValidatorTest do
  use ExUnit.Case, async: true

  alias GscAnalytics.PriorityUrls.{Entry, Validator}

  describe "validate_entry/1" do
    test "returns entry struct for valid payload" do
      payload = %{
        "url" => "https://Example.com/therapists/john-smith/",
        "priority_tier" => "P1",
        "page_type" => "profile",
        "notes" => "High converting therapist",
        "tags" => ["Therapist", " High-Intent "]
      }

      assert {:ok, %Entry{} = entry} = Validator.validate_entry(payload)
      assert entry.url == "https://Example.com/therapists/john-smith/"
      assert entry.priority_tier == "P1"
      assert entry.page_type == "profile"
      assert entry.notes == "High converting therapist"
      assert entry.tags == ["Therapist", "High-Intent"]
    end

    test "rejects entry missing required fields" do
      assert {:error, message} = Validator.validate_entry(%{})
      assert message =~ "required :url option"
    end

    test "rejects entry with invalid url" do
      payload = %{"url" => "example.com/path", "priority_tier" => "P1"}

      assert {:error, "Invalid URL: Missing protocol (http:// or https://)"} =
               Validator.validate_entry(payload)
    end

    test "rejects entry with invalid priority tier" do
      payload = %{"url" => "https://example.com", "priority_tier" => "High"}

      assert {:error, message} = Validator.validate_entry(payload)
      assert message =~ "Invalid priority_tier"
    end

    test "rejects entry with empty page_type" do
      payload = %{"url" => "https://example.com", "priority_tier" => "P1", "page_type" => " "}

      assert {:error, "Invalid page_type: Cannot be empty string. Omit field or use null."} =
               Validator.validate_entry(payload)
    end

    test "rejects entry when tags contain invalid values" do
      payload = %{
        "url" => "https://example.com",
        "priority_tier" => "P1",
        "tags" => ["valid", ""]
      }

      assert {:error, "tags cannot contain empty strings"} =
               Validator.validate_entry(payload)
    end

    test "rejects entry with unknown fields" do
      payload = %{"url" => "https://example.com", "priority_tier" => "P1", "extra" => "nope"}

      assert {:error, "Unknown fields: extra"} = Validator.validate_entry(payload)
    end
  end
end
