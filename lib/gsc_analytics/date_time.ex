defmodule GscAnalytics.DateTime do
  @moduledoc """
  Lightweight utilities for working with UTC timestamps in persistence layers.

  Phoenix defaults to second-precision `:utc_datetime` columns, so this helper
  ensures we consistently truncate to seconds before inserting values.
  """

  @spec utc_now() :: DateTime.t()
  def utc_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
