defmodule GscAnalytics.Schemas.SerpSnapshotSanitizationTest do
  use GscAnalytics.DataCase, async: true

  alias GscAnalytics.Schemas.SerpSnapshot

  describe "null byte sanitization" do
    test "removes null bytes from raw_response strings" do
      # Simulate ScrapFly response with null bytes (common in HTML)
      raw_response_with_nulls = %{
        "result" => %{
          "content" => "Hello\u0000World\u0000<div>Test</div>",
          "status" => 200
        },
        "config" => %{
          "url" => "https://google.com"
        }
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now(),
        raw_response: raw_response_with_nulls
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)

      assert changeset.valid?

      sanitized_response = Ecto.Changeset.get_change(changeset, :raw_response)

      # Null bytes should be removed
      assert sanitized_response["result"]["content"] == "HelloWorld<div>Test</div>"
      refute String.contains?(sanitized_response["result"]["content"], <<0>>)
    end

    test "handles nested maps and lists with null bytes" do
      raw_response = %{
        "data" => %{
          "items" => [
            %{"text" => "Item\u00001"},
            %{"text" => "Item\u00002"}
          ],
          "nested" => %{
            "deep" => "Value\u0000Here"
          }
        }
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now(),
        raw_response: raw_response
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)

      assert changeset.valid?

      sanitized = Ecto.Changeset.get_change(changeset, :raw_response)

      # Check all nested values are sanitized
      assert Enum.at(sanitized["data"]["items"], 0)["text"] == "Item1"
      assert Enum.at(sanitized["data"]["items"], 1)["text"] == "Item2"
      assert sanitized["data"]["nested"]["deep"] == "ValueHere"
    end

    test "can save snapshot with sanitized raw_response to database" do
      # This is the actual error we were seeing in production
      raw_response_with_nulls = %{
        "result" => %{
          "content" => "<html>Content\u0000with\u0000nulls</html>"
        }
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test keyword",
        position: 5,
        checked_at: DateTime.utc_now(),
        raw_response: raw_response_with_nulls,
        geo: "us"
      }

      # This should NOT raise a PostgreSQL error
      assert {:ok, snapshot} = %SerpSnapshot{}
                               |> SerpSnapshot.changeset(attrs)
                               |> Repo.insert()

      # Verify data was saved correctly (null bytes removed)
      assert snapshot.raw_response["result"]["content"] == "<html>Contentwithnulls</html>"
    end

    test "handles map keys with null bytes" do
      raw_response = %{
        "key\u0000with\u0000nulls" => "value"
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now(),
        raw_response: raw_response
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)

      assert changeset.valid?

      sanitized = Ecto.Changeset.get_change(changeset, :raw_response)

      # Key should be sanitized
      assert Map.has_key?(sanitized, "keywithnulls")
      assert sanitized["keywithnulls"] == "value"
    end

    test "preserves non-string values unchanged" do
      raw_response = %{
        "number" => 123,
        "boolean" => true,
        "null" => nil,
        "decimal" => 45.67
      }

      attrs = %{
        account_id: 1,
        property_url: "sc-domain:example.com",
        url: "https://example.com",
        keyword: "test",
        checked_at: DateTime.utc_now(),
        raw_response: raw_response
      }

      changeset = SerpSnapshot.changeset(%SerpSnapshot{}, attrs)

      sanitized = Ecto.Changeset.get_change(changeset, :raw_response)

      # Non-string values should remain unchanged
      assert sanitized["number"] == 123
      assert sanitized["boolean"] == true
      assert sanitized["null"] == nil
      assert sanitized["decimal"] == 45.67
    end
  end
end
