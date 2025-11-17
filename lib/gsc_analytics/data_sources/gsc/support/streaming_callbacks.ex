defmodule GscAnalytics.DataSources.GSC.Support.StreamingCallbacks do
  @moduledoc """
  Declarative container for query completion callbacks.

  A streaming callback has two phases:
    * `control` – runs synchronously inside the coordinator to decide whether
      pagination should continue. It must be quick and should never perform
      heavy IO.
    * `writer` – executed asynchronously to persist data and perform expensive
      work. Writer results are reported back to the coordinator.
  """

  defstruct control: nil,
            writer: nil,
            writer_timeout: 30_000,
            mode: :none

  @type t :: %__MODULE__{
          control: (map() -> :continue | {:halt, term()}) | nil,
          writer:
            (map() -> {:ok, term()} | {:halt, term()} | {:error, term()} | term())
            | nil,
          writer_timeout: non_neg_integer(),
          mode: :none | :legacy | :streaming
        }

  @doc """
  Normalize any callback input into a struct.

  Supported inputs:
    * `nil` – no callbacks
    * map/struct with `:control`, `:writer`, and optional `:writer_timeout`
    * function – treated as a legacy synchronous callback
  """
  @spec normalize(nil | map() | function()) :: t()
  def normalize(nil), do: %__MODULE__{mode: :none}

  def normalize(%__MODULE__{} = callbacks) do
    %{callbacks | mode: determine_mode(callbacks.control, callbacks.writer)}
  end

  def normalize(%{} = callbacks) do
    control = Map.get(callbacks, :control)
    writer = Map.get(callbacks, :writer)
    timeout = Map.get(callbacks, :writer_timeout, 30_000)

    %__MODULE__{
      control: control,
      writer: writer,
      writer_timeout: timeout,
      mode: determine_mode(control, writer)
    }
  end

  def normalize(fun) when is_function(fun, 1) do
    %__MODULE__{control: fun, writer: nil, writer_timeout: 30_000, mode: :legacy}
  end

  def normalize(_unsupported), do: %__MODULE__{mode: :none}

  defp determine_mode(nil, nil), do: :none
  defp determine_mode(_control, nil), do: :legacy
  defp determine_mode(_, _), do: :streaming
end
