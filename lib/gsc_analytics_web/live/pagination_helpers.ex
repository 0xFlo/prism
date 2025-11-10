defmodule GscAnalyticsWeb.Live.PaginationHelpers do
  @moduledoc """
  Shared pagination helpers for LiveView dashboards.

  Provides consistent parsing, validation, and calculation of pagination parameters
  across all dashboard views. This eliminates duplication and ensures consistent
  behavior for page numbers, limits, and visible page calculations.

  ## Usage

      defmodule MyDashboardLive do
        use GscAnalyticsWeb, :live_view
        import GscAnalyticsWeb.Live.PaginationHelpers

        def handle_params(params, _uri, socket) do
          page = parse_page(params["page"])
          limit = parse_limit(params["limit"])
          total_pages = calculate_total_pages(socket.assigns.total_count, limit)
          # ...
        end
      end
  """

  @default_limit 50
  @default_page 1
  @valid_limits [10, 25, 50, 100, 200, 500]

  @doc """
  Parse page number from query parameters.

  Returns a positive integer page number, defaulting to 1 for invalid input.

  ## Examples

      iex> parse_page("5")
      5

      iex> parse_page(nil)
      1

      iex> parse_page("invalid")
      1

      iex> parse_page(0)
      1
  """
  @spec parse_page(term()) :: pos_integer()
  def parse_page(nil), do: @default_page
  def parse_page(""), do: @default_page

  def parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {int, ""} when int > 0 -> int
      _ -> @default_page
    end
  end

  def parse_page(page) when is_integer(page) and page > 0, do: page
  def parse_page(_), do: @default_page

  @doc """
  Parse limit (items per page) from query parameters.

  Only accepts values from the whitelist: #{inspect(@valid_limits)}.
  Returns default limit (#{@default_limit}) for invalid input.

  ## Examples

      iex> parse_limit("100")
      100

      iex> parse_limit(nil)
      50

      iex> parse_limit("999")
      50
  """
  @spec parse_limit(term()) :: pos_integer()
  def parse_limit(nil), do: @default_limit
  def parse_limit(""), do: @default_limit

  def parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {int, ""} -> normalize_limit(int)
      _ -> @default_limit
    end
  end

  def parse_limit(limit) when is_integer(limit), do: normalize_limit(limit)
  def parse_limit(_), do: @default_limit

  @doc """
  Normalize limit to nearest valid value.

  Only accepts values from the whitelist: #{inspect(@valid_limits)}.

  ## Examples

      iex> normalize_limit(50)
      50

      iex> normalize_limit(75)
      50
  """
  @spec normalize_limit(integer()) :: pos_integer()
  def normalize_limit(limit) when limit in @valid_limits, do: limit
  def normalize_limit(_), do: @default_limit

  @doc """
  Calculate total number of pages given total item count and items per page.

  Always returns at least 1 page, even for empty result sets.

  ## Examples

      iex> calculate_total_pages(150, 50)
      3

      iex> calculate_total_pages(100, 50)
      2

      iex> calculate_total_pages(0, 50)
      1
  """
  @spec calculate_total_pages(non_neg_integer(), pos_integer()) :: pos_integer()
  def calculate_total_pages(0, _limit), do: 1

  def calculate_total_pages(total_count, limit) when total_count > 0 and limit > 0 do
    Float.ceil(total_count / limit) |> trunc()
  end

  def calculate_total_pages(_, _), do: 1

  @doc """
  Calculate visible page numbers for pagination UI with ellipsis.

  Shows up to 7 page numbers with ellipsis for gaps. Uses smart logic to
  show pages near current position while always showing first and last.

  ## Examples

      iex> calculate_visible_pages(1, 5)
      [1, 2, 3, 4, 5]

      iex> calculate_visible_pages(5, 10)
      [1, :ellipsis, 4, 5, 6, :ellipsis, 10]

      iex> calculate_visible_pages(1, 10)
      [1, 2, 3, 4, 5, :ellipsis, 10]
  """
  @spec calculate_visible_pages(pos_integer(), pos_integer()) :: list(pos_integer() | :ellipsis)
  def calculate_visible_pages(_current, total) when total <= 7 do
    # If 7 or fewer pages, show all
    Enum.to_list(1..total)
  end

  def calculate_visible_pages(current, total) when current <= 4 do
    # Near the start: [1, 2, 3, 4, 5, ..., last]
    [1, 2, 3, 4, 5, :ellipsis, total]
  end

  def calculate_visible_pages(current, total) when current >= total - 3 do
    # Near the end: [1, ..., last-4, last-3, last-2, last-1, last]
    [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]
  end

  def calculate_visible_pages(current, total) do
    # In the middle: [1, ..., current-1, current, current+1, ..., last]
    [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
  end

  @doc """
  Calculate start and end item numbers for current page display.

  Returns tuple of {start_item, end_item} for "Showing X to Y of Z" displays.

  ## Examples

      iex> calculate_item_range(1, 50, 150)
      {1, 50}

      iex> calculate_item_range(3, 50, 150)
      {101, 150}

      iex> calculate_item_range(2, 50, 75)
      {51, 75}
  """
  @spec calculate_item_range(pos_integer(), pos_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  def calculate_item_range(page, limit, total_count) do
    start_item = (page - 1) * limit + 1
    end_item = min(page * limit, total_count)
    {start_item, end_item}
  end

  @doc """
  Get list of valid limit options for dropdown menus.

  ## Examples

      iex> valid_limits()
      [10, 25, 50, 100, 200, 500]
  """
  @spec valid_limits() :: list(pos_integer())
  def valid_limits, do: @valid_limits

  @doc """
  Get default limit value.

  ## Examples

      iex> default_limit()
      50
  """
  @spec default_limit() :: pos_integer()
  def default_limit, do: @default_limit
end
