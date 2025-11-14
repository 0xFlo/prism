defmodule GscAnalytics.PriorityUrls.Entry do
  @moduledoc """
  Represents a single priority URL entry from JSON import.

  This struct enforces required fields and provides a clear data structure
  for the import pipeline.
  """

  @enforce_keys [:url, :priority_tier]
  defstruct url: nil,
            priority_tier: nil,
            page_type: nil,
            notes: nil,
            tags: [],
            source_file: nil

  @type t :: %__MODULE__{
          url: String.t(),
          priority_tier: String.t(),
          page_type: String.t() | nil,
          notes: String.t() | nil,
          tags: [String.t()],
          source_file: String.t() | nil
        }
end
