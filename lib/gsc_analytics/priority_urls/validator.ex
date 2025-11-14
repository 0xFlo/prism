defmodule GscAnalytics.PriorityUrls.Validator do
  @moduledoc """
  Validates priority URL entries produced by the JSON import pipeline.

  The validator keeps the schema enforcement logic in one place using
  `NimbleOptions`, ensuring the Mix task and any future ingestion paths
  share the exact same rules.
  """

  alias GscAnalytics.PriorityUrls.Entry
  alias NimbleOptions

  @priority_tiers ~w(P1 P2 P3 P4)

  @string_key_map %{
    "url" => :url,
    "priority_tier" => :priority_tier,
    "page_type" => :page_type,
    "notes" => :notes,
    "tags" => :tags,
    "source_file" => :source_file
  }

  @allowed_keys Map.values(@string_key_map)

  @entry_schema [
    url: [type: :string, required: true, doc: "Fully-qualified URL including protocol"],
    priority_tier: [
      type: :string,
      required: true,
      doc: "Priority tier value (P1-P4) provided by the client"
    ],
    page_type: [type: :string, required: false, doc: "Optional manual page type"],
    notes: [type: :string, required: false, doc: "Optional human readable notes"],
    tags: [type: :any, required: false, doc: "Optional array of tags (validated manually)"],
    source_file: [type: :string, required: false, doc: "File path used during import"]
  ]

  @doc """
  Validates and normalizes a single JSON entry.

  Returns `{:ok, %Entry{}}` on success or `{:error, message}` on failure.
  """
  @spec validate_entry(map()) :: {:ok, Entry.t()} | {:error, String.t()}
  def validate_entry(entry_map) when is_map(entry_map) do
    {normalized_map, unknown_keys} = normalize_keys(entry_map)

    case unknown_keys do
      [] -> :ok
      _ -> {:error, "Unknown fields: #{format_unknown_keys(unknown_keys)}"}
    end
    |> case do
      :ok -> run_schema_validation(normalized_map)
      {:error, _} = error -> error
    end
  end

  def validate_entry(_), do: {:error, "Entry must be a map"}

  defp run_schema_validation(normalized_map) do
    case normalized_map |> Map.to_list() |> NimbleOptions.validate(@entry_schema) do
      {:ok, opts} ->
        opts_map = Map.new(opts)

        with {:ok, url} <- validate_url(Map.fetch!(opts_map, :url)),
             {:ok, priority_tier} <- validate_priority_tier(Map.fetch!(opts_map, :priority_tier)),
             {:ok, page_type} <- validate_page_type(Map.get(opts_map, :page_type)),
             {:ok, tags} <- validate_tags(Map.get(opts_map, :tags)) do
          entry = %Entry{
            url: url,
            priority_tier: priority_tier,
            page_type: page_type,
            notes: Map.get(opts_map, :notes),
            tags: tags,
            source_file: Map.get(opts_map, :source_file)
          }

          {:ok, entry}
        else
          {:error, _} = error -> error
        end

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc """
  Validates URL format and returns the trimmed string.
  """
  @spec validate_url(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_url(url) when is_binary(url) do
    trimmed = String.trim(url)
    uri = URI.parse(trimmed)

    cond do
      trimmed == "" ->
        {:error, "Invalid URL: Cannot be blank"}

      is_nil(uri.scheme) or uri.scheme not in ["http", "https"] ->
        {:error, "Invalid URL: Missing protocol (http:// or https://)"}

      is_nil(uri.host) or uri.host == "" ->
        {:error, "Invalid URL: Missing or invalid hostname"}

      true ->
        {:ok, trimmed}
    end
  end

  def validate_url(_), do: {:error, "URL must be a string"}

  @doc """
  Ensures the provided tier is exactly one of `P1`..`P4`.
  """
  @spec validate_priority_tier(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_priority_tier(tier) when tier in @priority_tiers, do: {:ok, tier}

  def validate_priority_tier(tier) when is_binary(tier) do
    {:error,
     "Invalid priority_tier: '#{tier}'. Must be one of: #{Enum.join(@priority_tiers, ", ")}"}
  end

  def validate_priority_tier(_), do: {:error, "priority_tier must be a string"}

  @doc """
  Validates optional page type values.
  """
  @spec validate_page_type(String.t() | nil) :: {:ok, String.t() | nil} | {:error, String.t()}
  def validate_page_type(nil), do: {:ok, nil}

  def validate_page_type(page_type) when is_binary(page_type) do
    trimmed = String.trim(page_type)

    if trimmed == "" do
      {:error, "Invalid page_type: Cannot be empty string. Omit field or use null."}
    else
      {:ok, trimmed}
    end
  end

  def validate_page_type(_), do: {:error, "page_type must be a string"}

  defp validate_tags(nil), do: {:ok, []}

  defp validate_tags(tags) when is_list(tags) do
    tags
    |> Enum.reduce_while({:ok, []}, fn
      tag, {:ok, acc} when is_binary(tag) ->
        trimmed = String.trim(tag)

        if trimmed == "" do
          {:halt, {:error, "tags cannot contain empty strings"}}
        else
          {:cont, {:ok, [trimmed | acc]}}
        end

      _non_string, _ ->
        {:halt, {:error, "tags must be an array of strings"}}
    end)
    |> case do
      {:ok, tags_acc} -> {:ok, Enum.reverse(tags_acc)}
      {:error, _} = error -> error
    end
  end

  defp validate_tags(_), do: {:error, "tags must be an array of strings"}

  defp normalize_keys(map) do
    Enum.reduce(map, {%{}, []}, fn {key, value}, {acc, unknown} ->
      case normalize_key(key) do
        {:ok, normalized_key} ->
          {Map.put(acc, normalized_key, value), unknown}

        :unknown ->
          {acc, [key | unknown]}
      end
    end)
  end

  defp normalize_key(key) when is_atom(key) and key in @allowed_keys, do: {:ok, key}

  defp normalize_key(key) when is_binary(key) do
    case Map.fetch(@string_key_map, key) do
      {:ok, atom_key} -> {:ok, atom_key}
      :error -> :unknown
    end
  end

  defp normalize_key(_), do: :unknown

  defp format_unknown_keys(keys) do
    keys
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(", ")
  end
end
