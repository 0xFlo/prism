defmodule GscAnalytics.QueryParams do
  @moduledoc """
  Shared query parameter normalization and validation functions.

  Consolidates duplicated normalization logic that was previously scattered across:
  - `GscAnalytics.ContentInsights.UrlPerformance`
  - `GscAnalytics.ContentInsights.KeywordAggregator`
  - `GscAnalyticsWeb.Live.PaginationHelpers` (partial overlap)

  This module provides consistent, well-tested parameter parsing for:
  - Pagination (page numbers, limits)
  - Sorting (direction, column names)
  - Filtering (various data types)

  ## Design Philosophy

  - **Fail gracefully**: Always return sensible defaults for invalid input
  - **Type flexibility**: Accept strings, integers, atoms, or nil
  - **Recursive normalization**: Parse strings first, then normalize to correct range
  - **Configurable bounds**: Allow callers to specify min/max constraints

  ## Examples

      iex> QueryParams.normalize_limit("50")
      50

      iex> QueryParams.normalize_limit("9999")
      1000

      iex> QueryParams.normalize_page(nil)
      1

      iex> QueryParams.normalize_sort_direction("asc")
      :asc

      iex> QueryParams.normalize_sort_direction("invalid")
      :desc
  """

  @type sort_direction :: :asc | :desc

  # Default values
  @default_limit 100
  @default_page 1
  @default_sort_direction :desc

  # Constraints
  @max_limit 1000
  @min_limit 1

  # ============================================================================
  # PUBLIC API - LIMIT NORMALIZATION
  # ============================================================================

  @doc """
  Normalize limit (items per page) to a safe integer value.

  Accepts:
  - `nil` → returns default (#{@default_limit})
  - String integers (e.g., "50") → parsed and clamped
  - Integers → clamped to valid range
  - Invalid input → returns default

  The limit is clamped between #{@min_limit} and the configured max (default: #{@max_limit}).

  ## Options

  - `:default` - Default value to return for nil/invalid (default: #{@default_limit})
  - `:max` - Maximum allowed limit (default: #{@max_limit})
  - `:min` - Minimum allowed limit (default: #{@min_limit})

  ## Examples

      iex> QueryParams.normalize_limit(nil)
      100

      iex> QueryParams.normalize_limit("50")
      50

      iex> QueryParams.normalize_limit("9999")
      1000

      iex> QueryParams.normalize_limit(5, max: 10)
      5

      iex> QueryParams.normalize_limit("invalid")
      100

      iex> QueryParams.normalize_limit(0)
      100

      iex> QueryParams.normalize_limit(-5)
      100
  """
  @spec normalize_limit(term(), keyword()) :: pos_integer()
  def normalize_limit(value, opts \\ [])

  def normalize_limit(nil, opts) do
    Keyword.get(opts, :default, @default_limit)
  end

  def normalize_limit(limit, opts) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} -> normalize_limit(value, opts)
      _ -> Keyword.get(opts, :default, @default_limit)
    end
  end

  def normalize_limit(limit, opts) when is_integer(limit) and limit > 0 do
    max_limit = Keyword.get(opts, :max, @max_limit)
    min_limit = Keyword.get(opts, :min, @min_limit)

    limit
    |> min(max_limit)
    |> max(min_limit)
  end

  def normalize_limit(_, opts) do
    Keyword.get(opts, :default, @default_limit)
  end

  # ============================================================================
  # PUBLIC API - PAGE NORMALIZATION
  # ============================================================================

  @doc """
  Normalize page number to a positive integer.

  Accepts:
  - `nil` → returns 1
  - String integers (e.g., "2") → parsed
  - Positive integers → returned as-is
  - Invalid input → returns 1

  Always returns a positive integer >= 1.

  ## Examples

      iex> QueryParams.normalize_page(nil)
      1

      iex> QueryParams.normalize_page("5")
      5

      iex> QueryParams.normalize_page(10)
      10

      iex> QueryParams.normalize_page("invalid")
      1

      iex> QueryParams.normalize_page(0)
      1

      iex> QueryParams.normalize_page(-3)
      1
  """
  @spec normalize_page(term()) :: pos_integer()
  def normalize_page(nil), do: @default_page

  def normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} -> normalize_page(value)
      _ -> @default_page
    end
  end

  def normalize_page(page) when is_integer(page) and page > 0, do: page
  def normalize_page(_), do: @default_page

  # ============================================================================
  # PUBLIC API - SORT DIRECTION NORMALIZATION
  # ============================================================================

  @doc """
  Normalize sort direction to an atom (`:asc` or `:desc`).

  Accepts:
  - `nil` → `:desc`
  - Strings: "asc", "desc" → converted to atoms
  - Atoms: `:asc`, `:desc` → returned as-is
  - Invalid input → `:desc`

  ## Examples

      iex> QueryParams.normalize_sort_direction(nil)
      :desc

      iex> QueryParams.normalize_sort_direction("asc")
      :asc

      iex> QueryParams.normalize_sort_direction(:asc)
      :asc

      iex> QueryParams.normalize_sort_direction("desc")
      :desc

      iex> QueryParams.normalize_sort_direction(:desc)
      :desc

      iex> QueryParams.normalize_sort_direction("invalid")
      :desc

      iex> QueryParams.normalize_sort_direction(:invalid)
      :desc
  """
  @spec normalize_sort_direction(term()) :: sort_direction()
  def normalize_sort_direction(nil), do: @default_sort_direction
  def normalize_sort_direction("asc"), do: :asc
  def normalize_sort_direction(:asc), do: :asc
  def normalize_sort_direction("desc"), do: :desc
  def normalize_sort_direction(:desc), do: :desc
  def normalize_sort_direction(_), do: @default_sort_direction

  # ============================================================================
  # PUBLIC API - CONFIGURATION ACCESS
  # ============================================================================

  @doc """
  Get the default limit value.

  ## Examples

      iex> QueryParams.default_limit()
      100
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit

  @doc """
  Get the default page value.

  ## Examples

      iex> QueryParams.default_page()
      1
  """
  @spec default_page() :: pos_integer()
  def default_page, do: @default_page

  @doc """
  Get the default sort direction.

  ## Examples

      iex> QueryParams.default_sort_direction()
      :desc
  """
  @spec default_sort_direction() :: sort_direction()
  def default_sort_direction, do: @default_sort_direction

  @doc """
  Get the maximum allowed limit.

  ## Examples

      iex> QueryParams.max_limit()
      1000
  """
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit
end
