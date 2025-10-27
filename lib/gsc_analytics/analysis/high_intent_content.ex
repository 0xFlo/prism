defmodule GscAnalytics.Analysis.HighIntentContent do
  @moduledoc """
  Utilities for surfacing high-intent conversion content from the local
  Scrapfly markdown corpus. High-intent pages target commercial research terms
  such as comparisons, alternatives, pricing, and best-of roundups. The module
  runs entirely offline using keyword heuristics so it can be executed in
  environments without API access.
  """

  @high_intent_patterns [
    ~r/\bvs\b/i,
    ~r/versus/i,
    ~r/alternatives?/i,
    ~r/alternative\b/i,
    ~r/replace(?:ment)?/i,
    ~r/compare|comparison/i,
    ~r/competitors?/i,
    ~r/migrate|migration/i,
    ~r/\bswitch(?:ing)?/i,
    ~r/\bbest\b/i,
    ~r/\btop\b/i,
    ~r/providers?/i,
    ~r/pricing/i,
    ~r/cost|total cost|tco/i,
    ~r/roi/i,
    ~r/review/i,
    ~r/roundup/i
  ]

  @default_dir Path.join([File.cwd!(), "scrapfly", "blog-posts"])

  @doc """
  Return a list of metadata maps for markdown files that appear to be
  high-intent conversion content.

  Each map contains:
    * `:path`     – absolute file path
    * `:filename` – markdown filename
    * `:title`    – front-matter title (if present)
    * `:url`      – canonical URL from front matter (if present)
    * `:score`    – number of matched high-intent keyword patterns
    * `:signals`  – human readable list of matched signals
  """
  @spec list_high_intent_posts(Path.t()) :: [map()]
  def list_high_intent_posts(dir \\ @default_dir) do
    dir
    |> Path.join("*.md")
    |> Path.wildcard()
    |> Enum.map(&extract_metadata/1)
    |> Enum.map(&enrich_if_high_intent/1)
    |> Enum.filter(& &1)
    |> Enum.sort_by(&{&1.score * -1, String.downcase(&1.title || &1.filename)})
  end

  @doc """
  Emit a CSV string from the provided high-intent entries for easy exporting.
  """
  @spec to_csv([map()]) :: String.t()
  def to_csv(entries) when is_list(entries) do
    header = "title,url,filename,score,signals\n"

    rows =
      entries
      |> Enum.map(fn entry ->
        [
          entry.title,
          entry.url,
          entry.filename,
          Integer.to_string(entry.score),
          Enum.join(entry.signals, " ")
        ]
        |> Enum.map(&escape_csv/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    header <> rows <> "\n"
  end

  @doc """
  Convenience helper that scans the default directory and prints a concise
  report to STDOUT.
  """
  def print_report(dir \\ @default_dir) do
    dir
    |> list_high_intent_posts()
    |> Enum.each(fn entry ->
      IO.puts("- #{entry.title || entry.filename} (score=#{entry.score})")
      IO.puts("  URL: #{entry.url || "n/a"}")
      IO.puts("  Signals: #{Enum.join(entry.signals, ", ")}")
      IO.puts("")
    end)
  end

  defp extract_metadata(path) do
    content = File.read!(path)
    {front_matter, _body} = split_front_matter(content)

    %{
      path: path,
      filename: Path.basename(path),
      title: capture_field(front_matter, "title"),
      url: capture_field(front_matter, "url"),
      description: capture_field(front_matter, "description"),
      tags: capture_tags(front_matter)
    }
  end

  defp split_front_matter(content) do
    case String.split(content, "\n---\n", parts: 2) do
      ["---" <> rest, body] ->
        front = String.trim_leading(rest, "\n")
        {front, body}

      _ ->
        {"", content}
    end
  end

  defp capture_field(front_matter, field) do
    regex = ~r/^#{field}:\s*(.+)$/m

    case Regex.run(regex, front_matter) do
      [_, value] ->
        value
        |> String.trim()
        |> String.trim("'")

      _ ->
        nil
    end
  end

  defp capture_tags(front_matter) do
    case Regex.run(~r/^tags:\s*\n(.*?)\n(?:\w+:|\z)/ms, front_matter) do
      [_, block] ->
        block
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "- "))
        |> Enum.map(fn "- " <> tag -> String.trim(tag) end)

      _ ->
        []
    end
  end

  defp enrich_if_high_intent(metadata) do
    text =
      [metadata.title, metadata.description, metadata.filename | metadata.tags]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" \n")

    signals =
      @high_intent_patterns
      |> Enum.filter(&Regex.match?(&1, text))
      |> Enum.map(&pattern_to_label/1)
      |> Enum.uniq()

    score = length(signals)

    if score > 0 do
      Map.merge(metadata, %{score: score, signals: signals})
    end
  end

  defp pattern_to_label(~r/\bvs\b/i), do: "vs"
  defp pattern_to_label(~r/versus/i), do: "vs"
  defp pattern_to_label(~r/alternatives?/i), do: "alternatives"
  defp pattern_to_label(~r/alternative\b/i), do: "alternatives"
  defp pattern_to_label(~r/replace(?:ment)?/i), do: "replacement"
  defp pattern_to_label(~r/compare|comparison/i), do: "comparison"
  defp pattern_to_label(~r/competitors?/i), do: "competitors"
  defp pattern_to_label(~r/migrate|migration/i), do: "migration"
  defp pattern_to_label(~r/\bswitch(?:ing)?/i), do: "switch"
  defp pattern_to_label(~r/\bbest\b/i), do: "best"
  defp pattern_to_label(~r/\btop\b/i), do: "top"
  defp pattern_to_label(~r/providers?/i), do: "providers"
  defp pattern_to_label(~r/pricing/i), do: "pricing"
  defp pattern_to_label(~r/cost|total cost|tco/i), do: "cost"
  defp pattern_to_label(~r/roi/i), do: "roi"
  defp pattern_to_label(~r/review/i), do: "review"
  defp pattern_to_label(~r/roundup/i), do: "roundup"

  defp escape_csv(nil), do: ""

  defp escape_csv(value) do
    value = to_string(value)

    # Quote fields containing commas, quotes, newlines, or spaces (RFC 4180 + spaces for safety)
    if String.contains?(value, [",", "\"", "\n", " "]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
end
