defmodule GscAnalytics.ChangesetValidatorsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import GscAnalytics.ChangesetValidators

  # Define a test schema for changeset testing
  defmodule TestSchema do
    use Ecto.Schema

    embedded_schema do
      field(:url, :string)
      field(:property_url, :string)
      field(:redirect_url, :string)
      field(:clicks, :integer)
      field(:impressions, :integer)
      field(:ctr, :float)
      field(:position, :float)
      field(:http_status, :integer)
      field(:start_date, :date)
      field(:end_date, :date)
      field(:account_id, :integer)
      field(:name, :string)
    end
  end

  # Helper to create a changeset for testing
  defp test_changeset(attrs) do
    %TestSchema{}
    |> cast(attrs, [
      :url,
      :property_url,
      :redirect_url,
      :clicks,
      :impressions,
      :ctr,
      :position,
      :http_status,
      :start_date,
      :end_date,
      :account_id,
      :name
    ])
  end

  # ============================================================================
  # URL VALIDATION TESTS
  # ============================================================================

  describe "validate_http_url/3" do
    test "accepts valid HTTPS URLs" do
      changeset =
        test_changeset(%{url: "https://example.com"})
        |> validate_http_url(:url)

      assert changeset.valid?
    end

    test "accepts valid HTTP URLs" do
      changeset =
        test_changeset(%{url: "http://example.com"})
        |> validate_http_url(:url)

      assert changeset.valid?
    end

    test "accepts URLs with paths and query strings" do
      changeset =
        test_changeset(%{url: "https://example.com/path?query=value"})
        |> validate_http_url(:url)

      assert changeset.valid?
    end

    test "rejects URLs without scheme" do
      changeset =
        test_changeset(%{url: "example.com"})
        |> validate_http_url(:url)

      refute changeset.valid?
      assert errors_on(changeset)[:url] == ["must be a valid HTTP(S) URL"]
    end

    test "rejects URLs with invalid scheme" do
      changeset =
        test_changeset(%{url: "ftp://example.com"})
        |> validate_http_url(:url)

      refute changeset.valid?
      assert errors_on(changeset)[:url] == ["must be a valid HTTP(S) URL"]
    end

    test "rejects URLs without host" do
      # URI.parse("https://") returns host: "" (empty string)
      changeset =
        test_changeset(%{url: "https://"})
        |> validate_http_url(:url)

      refute changeset.valid?
      assert errors_on(changeset)[:url] == ["must be a valid HTTP(S) URL"]
    end

    test "accepts custom error message" do
      changeset =
        test_changeset(%{url: "invalid"})
        |> validate_http_url(:url, message: "custom error")

      assert errors_on(changeset)[:url] == ["custom error"]
    end

    test "skips validation when field is not in changeset" do
      changeset =
        test_changeset(%{})
        |> validate_http_url(:url)

      assert changeset.valid?
    end
  end

  describe "validate_url_length/3" do
    test "accepts URLs within default length (2048 chars)" do
      url = "https://example.com/" <> String.duplicate("a", 2020)

      changeset =
        test_changeset(%{url: url})
        |> validate_url_length(:url)

      assert changeset.valid?
    end

    test "rejects URLs exceeding default length" do
      url = "https://example.com/" <> String.duplicate("a", 2030)

      changeset =
        test_changeset(%{url: url})
        |> validate_url_length(:url)

      refute changeset.valid?
      [error_message] = errors_on(changeset)[:url]
      assert String.contains?(error_message, "URL too long")
    end

    test "accepts custom max length" do
      changeset =
        test_changeset(%{url: "https://example.com/short"})
        |> validate_url_length(:url, max: 50)

      assert changeset.valid?
    end

    test "rejects URLs exceeding custom max length" do
      changeset =
        test_changeset(%{url: "https://example.com/this-is-a-very-long-url"})
        |> validate_url_length(:url, max: 20)

      refute changeset.valid?
    end
  end

  # ============================================================================
  # METRIC VALIDATION TESTS
  # ============================================================================

  describe "validate_ctr_range/2" do
    test "accepts valid CTR values" do
      for ctr <- [0.0, 0.25, 0.5, 0.75, 1.0] do
        changeset =
          test_changeset(%{ctr: ctr})
          |> validate_ctr_range()

        assert changeset.valid?, "CTR #{ctr} should be valid"
      end
    end

    test "rejects CTR below 0" do
      changeset =
        test_changeset(%{ctr: -0.1})
        |> validate_ctr_range()

      refute changeset.valid?
    end

    test "rejects CTR above 1.0" do
      changeset =
        test_changeset(%{ctr: 1.1})
        |> validate_ctr_range()

      refute changeset.valid?
    end

    test "accepts custom field name" do
      changeset =
        %TestSchema{}
        |> cast(%{position: 0.5}, [:position])
        |> validate_ctr_range(:position)

      assert changeset.valid?
    end
  end

  describe "validate_position_range/2" do
    test "accepts valid position values" do
      for position <- [0.0, 1.0, 10.5, 100.0] do
        changeset =
          test_changeset(%{position: position})
          |> validate_position_range()

        assert changeset.valid?, "Position #{position} should be valid"
      end
    end

    test "rejects negative position" do
      changeset =
        test_changeset(%{position: -1.0})
        |> validate_position_range()

      refute changeset.valid?
    end
  end

  describe "validate_count_metric/2" do
    test "accepts zero and positive counts" do
      for count <- [0, 1, 100, 1_000_000] do
        changeset =
          test_changeset(%{clicks: count})
          |> validate_count_metric(:clicks)

        assert changeset.valid?, "Count #{count} should be valid"
      end
    end

    test "rejects negative counts" do
      changeset =
        test_changeset(%{clicks: -1})
        |> validate_count_metric(:clicks)

      refute changeset.valid?
    end
  end

  describe "validate_gsc_metrics/1" do
    test "validates all metrics at once" do
      changeset =
        test_changeset(%{
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.5
        })
        |> validate_gsc_metrics()

      assert changeset.valid?
    end

    test "catches any invalid metric" do
      changeset =
        test_changeset(%{
          clicks: 100,
          impressions: -50,
          # Invalid!
          ctr: 0.1,
          position: 5.5
        })
        |> validate_gsc_metrics()

      refute changeset.valid?
      assert errors_on(changeset)[:impressions]
    end

    test "catches multiple invalid metrics" do
      changeset =
        test_changeset(%{
          clicks: -10,
          # Invalid!
          impressions: -50,
          # Invalid!
          ctr: 1.5,
          # Invalid!
          position: -2.0
          # Invalid!
        })
        |> validate_gsc_metrics()

      refute changeset.valid?
      assert errors_on(changeset)[:clicks]
      assert errors_on(changeset)[:impressions]
      assert errors_on(changeset)[:ctr]
      assert errors_on(changeset)[:position]
    end
  end

  # ============================================================================
  # DATE VALIDATION TESTS
  # ============================================================================

  describe "validate_date_range/4" do
    test "accepts valid date range" do
      changeset =
        test_changeset(%{
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-31]
        })
        |> validate_date_range(:start_date, :end_date)

      assert changeset.valid?
    end

    test "accepts same start and end date" do
      changeset =
        test_changeset(%{
          start_date: ~D[2024-01-01],
          end_date: ~D[2024-01-01]
        })
        |> validate_date_range(:start_date, :end_date)

      assert changeset.valid?
    end

    test "rejects start date after end date" do
      changeset =
        test_changeset(%{
          start_date: ~D[2024-01-31],
          end_date: ~D[2024-01-01]
        })
        |> validate_date_range(:start_date, :end_date)

      refute changeset.valid?
      assert errors_on(changeset)[:start_date] == ["must be before or equal to end date"]
    end

    test "skips validation when both dates are nil" do
      changeset =
        test_changeset(%{})
        |> validate_date_range(:start_date, :end_date)

      assert changeset.valid?
    end

    test "skips validation when only start date is present" do
      changeset =
        test_changeset(%{start_date: ~D[2024-01-01]})
        |> validate_date_range(:start_date, :end_date)

      assert changeset.valid?
    end

    test "skips validation when only end date is present" do
      changeset =
        test_changeset(%{end_date: ~D[2024-01-31]})
        |> validate_date_range(:start_date, :end_date)

      assert changeset.valid?
    end

    test "accepts custom error message" do
      changeset =
        test_changeset(%{
          start_date: ~D[2024-01-31],
          end_date: ~D[2024-01-01]
        })
        |> validate_date_range(:start_date, :end_date, message: "custom date error")

      assert errors_on(changeset)[:start_date] == ["custom date error"]
    end
  end

  # ============================================================================
  # HTTP STATUS VALIDATION TESTS
  # ============================================================================

  describe "validate_http_status/2" do
    test "accepts valid HTTP status codes" do
      valid_codes = [100, 200, 201, 301, 302, 400, 404, 500, 503, 599]

      for code <- valid_codes do
        changeset =
          test_changeset(%{http_status: code})
          |> validate_http_status()

        assert changeset.valid?, "HTTP status #{code} should be valid"
      end
    end

    test "rejects status codes below 100" do
      changeset =
        test_changeset(%{http_status: 99})
        |> validate_http_status()

      refute changeset.valid?
    end

    test "rejects status codes above 599" do
      changeset =
        test_changeset(%{http_status: 600})
        |> validate_http_status()

      refute changeset.valid?
    end

    test "skips validation when status is nil" do
      changeset =
        test_changeset(%{})
        |> validate_http_status()

      assert changeset.valid?
    end
  end

  # ============================================================================
  # HELPER VALIDATOR TESTS
  # ============================================================================

  describe "validate_not_empty/3" do
    test "accepts non-empty string" do
      changeset =
        test_changeset(%{name: "John Doe"})
        |> validate_not_empty(:name)

      assert changeset.valid?
    end

    test "rejects nil" do
      changeset =
        test_changeset(%{name: nil})
        |> validate_not_empty(:name)

      refute changeset.valid?
      assert errors_on(changeset)[:name] == ["can't be blank"]
    end

    test "rejects empty string" do
      changeset =
        test_changeset(%{name: ""})
        |> validate_not_empty(:name)

      refute changeset.valid?
      assert errors_on(changeset)[:name] == ["can't be blank"]
    end

    test "accepts custom error message" do
      changeset =
        test_changeset(%{name: ""})
        |> validate_not_empty(:name, message: "is required")

      assert errors_on(changeset)[:name] == ["is required"]
    end
  end

  describe "validate_positive_integer/3" do
    test "accepts positive integers" do
      for value <- [1, 10, 100, 1_000_000] do
        changeset =
          test_changeset(%{account_id: value})
          |> validate_positive_integer(:account_id)

        assert changeset.valid?, "Value #{value} should be valid"
      end
    end

    test "rejects zero" do
      changeset =
        test_changeset(%{account_id: 0})
        |> validate_positive_integer(:account_id)

      refute changeset.valid?
    end

    test "rejects negative integers" do
      changeset =
        test_changeset(%{account_id: -1})
        |> validate_positive_integer(:account_id)

      refute changeset.valid?
    end

    test "accepts custom error message" do
      changeset =
        test_changeset(%{account_id: 0})
        |> validate_positive_integer(:account_id, message: "must be positive")

      assert errors_on(changeset)[:account_id] == ["must be positive"]
    end
  end

  # ============================================================================
  # INTEGRATION TESTS - COMMON PATTERNS
  # ============================================================================

  describe "integration - Performance schema pattern" do
    test "validates complete Performance-like changeset" do
      changeset =
        test_changeset(%{
          url: "https://example.com/page",
          property_url: "sc-domain:example.com",
          clicks: 100,
          impressions: 1000,
          ctr: 0.1,
          position: 5.5,
          http_status: 200
        })
        |> validate_http_url(:url)
        |> validate_url_length(:url)
        |> validate_url_length(:property_url, max: 255)
        |> validate_gsc_metrics()
        |> validate_http_status()

      assert changeset.valid?
    end

    test "catches multiple validation failures" do
      changeset =
        test_changeset(%{
          url: "not-a-url",
          # Invalid URL
          property_url: String.duplicate("a", 300),
          # Too long
          clicks: -10,
          # Negative
          ctr: 1.5,
          # > 1.0
          http_status: 999
          # Invalid code
        })
        |> validate_http_url(:url)
        |> validate_url_length(:property_url, max: 255)
        |> validate_gsc_metrics()
        |> validate_http_status()

      refute changeset.valid?
      assert errors_on(changeset)[:url]
      assert errors_on(changeset)[:property_url]
      assert errors_on(changeset)[:clicks]
      assert errors_on(changeset)[:ctr]
      assert errors_on(changeset)[:http_status]
    end
  end

  # Helper function to extract error messages
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
