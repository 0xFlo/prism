defmodule GscAnalytics.ChangesetValidators do
  @moduledoc """
  Reusable Ecto changeset validation functions.

  Consolidates common validation logic that was previously scattered across schema modules.
  Provides consistent, well-tested validators for:
  - URL validation (format, scheme, host, length)
  - Metric ranges (CTR, position, counts)
  - Date ranges (start before end)
  - HTTP status codes

  ## Usage

      defmodule MySchema do
        use Ecto.Schema
        import Ecto.Changeset
        import GscAnalytics.ChangesetValidators

        def changeset(struct, attrs) do
          struct
          |> cast(attrs, [:url, :ctr, :start_date, :end_date])
          |> validate_http_url(:url)
          |> validate_ctr_range(:ctr)
          |> validate_date_range(:start_date, :end_date)
        end
      end

  ## Design Philosophy

  - **Reusable**: Each validator is a pure function accepting a changeset
  - **Composable**: Validators can be piped together
  - **Configurable**: Accept field names and options
  - **Documented**: All validators include @doc with examples
  """

  import Ecto.Changeset

  # ============================================================================
  # URL VALIDATION
  # ============================================================================

  @doc """
  Validates that a field contains a valid HTTP(S) URL.

  Checks:
  - URL can be parsed
  - Scheme is "http" or "https"
  - Host is present (not nil)

  ## Options

  - `:message` - Custom error message (default: "must be a valid HTTP(S) URL")

  ## Examples

      iex> changeset = %Schema{} |> cast(%{url: "https://example.com"}, [:url])
      iex> changeset = validate_http_url(changeset, :url)
      iex> changeset.valid?
      true

      iex> changeset = %Schema{} |> cast(%{url: "not-a-url"}, [:url])
      iex> changeset = validate_http_url(changeset, :url)
      iex> changeset.errors
      [url: {"must be a valid HTTP(S) URL", [...]}]
  """
  @spec validate_http_url(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_http_url(changeset, field, opts \\ []) do
    message = Keyword.get(opts, :message, "must be a valid HTTP(S) URL")

    validate_change(changeset, field, fn ^field, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and not is_nil(host) and host != "" ->
          []

        _ ->
          [{field, message}]
      end
    end)
  end

  @doc """
  Validates URL length constraints.

  ## Options

  - `:max` - Maximum URL length in characters (default: 2048)
  - `:message` - Custom error message

  ## Examples

      iex> changeset = validate_url_length(changeset, :url, max: 255)
  """
  @spec validate_url_length(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_url_length(changeset, field, opts \\ []) do
    max_length = Keyword.get(opts, :max, 2048)
    message = Keyword.get(opts, :message, "URL too long (maximum #{max_length} characters)")

    validate_length(changeset, field, max: max_length, message: message)
  end

  # ============================================================================
  # METRIC VALIDATION
  # ============================================================================

  @doc """
  Validates CTR (Click-Through Rate) is between 0.0 and 1.0.

  CTR is a percentage represented as a decimal (0.0 = 0%, 1.0 = 100%).

  ## Examples

      iex> changeset = validate_ctr_range(changeset, :ctr)
      # Accepts 0.0 to 1.0
  """
  @spec validate_ctr_range(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_ctr_range(changeset, field \\ :ctr) do
    validate_number(changeset, field,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end

  @doc """
  Validates position metric is >= 0.

  Search position cannot be negative (0 means no ranking data).

  ## Examples

      iex> changeset = validate_position_range(changeset, :position)
  """
  @spec validate_position_range(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_position_range(changeset, field \\ :position) do
    validate_number(changeset, field, greater_than_or_equal_to: 0.0)
  end

  @doc """
  Validates count metrics (clicks, impressions, etc.) are >= 0.

  ## Examples

      iex> changeset
      ...> |> validate_count_metric(:clicks)
      ...> |> validate_count_metric(:impressions)
  """
  @spec validate_count_metric(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_count_metric(changeset, field) do
    validate_number(changeset, field, greater_than_or_equal_to: 0)
  end

  @doc """
  Validates all standard GSC metrics at once.

  Validates:
  - `:clicks` >= 0
  - `:impressions` >= 0
  - `:ctr` between 0.0 and 1.0
  - `:position` >= 0.0

  ## Examples

      iex> changeset = validate_gsc_metrics(changeset)
  """
  @spec validate_gsc_metrics(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_gsc_metrics(changeset) do
    changeset
    |> validate_count_metric(:clicks)
    |> validate_count_metric(:impressions)
    |> validate_ctr_range(:ctr)
    |> validate_position_range(:position)
  end

  # ============================================================================
  # DATE VALIDATION
  # ============================================================================

  @doc """
  Validates that start date is before or equal to end date.

  Only validates if both dates are present. Skips validation if either is nil.

  ## Options

  - `:message` - Custom error message (default: "must be before or equal to end date")

  ## Examples

      iex> changeset = validate_date_range(changeset, :start_date, :end_date)

      iex> changeset = validate_date_range(changeset, :period_start, :period_end,
      ...>   message: "period start must be before period end")
  """
  @spec validate_date_range(Ecto.Changeset.t(), atom(), atom(), keyword()) ::
          Ecto.Changeset.t()
  def validate_date_range(changeset, start_field, end_field, opts \\ []) do
    message = Keyword.get(opts, :message, "must be before or equal to end date")

    case {get_change(changeset, start_field), get_change(changeset, end_field)} do
      {nil, nil} ->
        changeset

      {start_date, end_date} when not is_nil(start_date) and not is_nil(end_date) ->
        if Date.compare(start_date, end_date) == :gt do
          add_error(changeset, start_field, message)
        else
          changeset
        end

      _ ->
        changeset
    end
  end

  # ============================================================================
  # HTTP STATUS VALIDATION
  # ============================================================================

  @doc """
  Validates HTTP status code is in valid range (100-599).

  Allows nil (no status code yet).

  ## Examples

      iex> changeset = validate_http_status(changeset, :http_status)
  """
  @spec validate_http_status(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_http_status(changeset, field \\ :http_status) do
    validate_number(changeset, field,
      greater_than_or_equal_to: 100,
      less_than_or_equal_to: 599
    )
  end

  # ============================================================================
  # HELPER VALIDATORS
  # ============================================================================

  @doc """
  Validates field is present and not empty string.

  More strict than `validate_required/2` - also checks for empty strings.

  ## Examples

      iex> changeset = validate_not_empty(changeset, :url)
      # Rejects nil and ""
  """
  @spec validate_not_empty(Ecto.Changeset.t(), atom(), keyword()) :: Ecto.Changeset.t()
  def validate_not_empty(changeset, field, opts \\ []) do
    message = Keyword.get(opts, :message, "can't be blank")

    changeset
    |> validate_required([field], message: message)
    |> validate_change(field, fn ^field, value ->
      case value do
        "" -> [{field, message}]
        _ -> []
      end
    end)
  end

  @doc """
  Validates that an integer field is positive (> 0).

  ## Examples

      iex> changeset = validate_positive_integer(changeset, :account_id)
  """
  @spec validate_positive_integer(Ecto.Changeset.t(), atom(), keyword()) ::
          Ecto.Changeset.t()
  def validate_positive_integer(changeset, field, opts \\ []) do
    message = Keyword.get(opts, :message, "must be greater than 0")
    validate_number(changeset, field, greater_than: 0, message: message)
  end
end
