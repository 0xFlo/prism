defmodule GscAnalytics.Dashboard do
  @moduledoc """
  Parameter normalization helpers shared across dashboard LiveViews.
  """

  @default_limit 100
  @default_direction :desc

  @doc """
  Returns the default paging limit used by the dashboard.
  """
  def default_limit, do: @default_limit

  @doc """
  Parses a limit parameter (string or integer) and clamps it to 1..1000.
  """
  def normalize_limit(nil), do: @default_limit

  def normalize_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {value, ""} when value > 0 -> min(value, 1000)
      _ -> @default_limit
    end
  end

  def normalize_limit(limit) when is_integer(limit) and limit > 0 do
    min(limit, 1000)
  end

  def normalize_limit(_), do: @default_limit

  @doc """
  Parses a page parameter (string or integer) and ensures it's >= 1.
  """
  def normalize_page(nil), do: 1

  def normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> value
      _ -> 1
    end
  end

  def normalize_page(page) when is_integer(page) and page > 0, do: page
  def normalize_page(_), do: 1

  @doc """
  Validates a `sort_direction` parameter and returns `atom_direction`.
  Returns :asc or :desc, defaults to desc.
  """
  def normalize_sort_direction(nil), do: @default_direction
  def normalize_sort_direction("asc"), do: :asc
  def normalize_sort_direction("desc"), do: :desc
  def normalize_sort_direction(:asc), do: :asc
  def normalize_sort_direction(:desc), do: :desc
  def normalize_sort_direction(_), do: @default_direction
end
