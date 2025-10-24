# Diagnostic script to check for duplicate backlinks
#
# Usage: mix run scripts/check_backlink_duplicates.exs
#
# This script checks for:
# 1. True duplicates (same source_url + target_url appearing multiple times)
# 2. Domain-level aggregation to show what user sees in dashboard
# 3. URL normalization issues that might cause duplicates

require Logger
alias GscAnalytics.Repo

IO.puts("""

╔══════════════════════════════════════════════════════════╗
║  Backlink Duplicate Analysis                             ║
╚══════════════════════════════════════════════════════════╝

""")

# Check 1: True duplicates (violates unique constraint)
IO.puts("📋 Checking for TRUE duplicates (same source_url + target_url)...")

true_duplicates = Repo.query!("""
  SELECT source_url, target_url, data_source, first_seen_at, COUNT(*) as count
  FROM backlinks
  GROUP BY source_url, target_url, data_source, first_seen_at
  HAVING COUNT(*) > 1
  ORDER BY count DESC
""")

if true_duplicates.num_rows == 0 do
  IO.puts("✅ No true duplicates found!")
  IO.puts("   The unique constraint (source_url, target_url) is working correctly.\n")
else
  IO.puts("❌ Found #{true_duplicates.num_rows} groups of true duplicates:\n")

  Enum.each(true_duplicates.rows, fn [source_url, target_url, data_source, first_seen_at, count] ->
    IO.puts("   • #{count}x duplicates:")
    IO.puts("     Source: #{source_url}")
    IO.puts("     Target: #{target_url}")
    IO.puts("     Data source: #{data_source}")
    IO.puts("     First seen: #{first_seen_at}")
    IO.puts("")
  end)
end

# Check 2: Domain-level view (what user sees)
IO.puts("\n📊 Checking domain-level aggregation for Instagram scraper URL...")

instagram_url = "https://scrapfly.io/blog/how-to-scrape-instagram"

domain_aggregation = Repo.query!(
  """
  SELECT
    source_domain,
    anchor_text,
    first_seen_at,
    data_source,
    source_url
  FROM backlinks
  WHERE target_url = $1
  ORDER BY source_domain, first_seen_at
  """,
  [instagram_url]
)

# Group by domain to show multiple links from same domain
domains_with_multiple_links =
  domain_aggregation.rows
  |> Enum.group_by(fn [domain, _, _, _, _] -> domain end)
  |> Enum.filter(fn {_domain, rows} -> length(rows) > 1 end)
  |> Enum.sort_by(fn {domain, _} -> domain end)

if Enum.empty?(domains_with_multiple_links) do
  IO.puts("✅ No domains with multiple backlinks to Instagram scraper URL")
else
  IO.puts("📍 Domains with multiple backlinks (these LOOK like duplicates in the dashboard):\n")

  Enum.each(domains_with_multiple_links, fn {domain, links} ->
    IO.puts("   🌐 #{domain} (#{length(links)} backlinks):")

    Enum.each(links, fn [_domain, anchor, first_seen, source, source_url] ->
      IO.puts("      • Anchor: \"#{String.slice(anchor || "—", 0..50)}\"")
      IO.puts("        Date: #{first_seen}")
      IO.puts("        Source: #{source}")
      IO.puts("        URL: #{String.slice(source_url, 0..80)}")
      IO.puts("")
    end)

    IO.puts("")
  end)
end

# Check 3: URL normalization issues
IO.puts("\n🔍 Checking for potential URL normalization issues...")

normalization_check = Repo.query!("""
  WITH normalized AS (
    SELECT
      LOWER(TRIM(source_url)) as norm_source,
      LOWER(TRIM(target_url)) as norm_target,
      source_url,
      target_url,
      data_source
    FROM backlinks
  )
  SELECT
    norm_source,
    norm_target,
    COUNT(*) as variant_count,
    STRING_AGG(DISTINCT source_url, ' | ') as url_variants
  FROM normalized
  GROUP BY norm_source, norm_target
  HAVING COUNT(*) > 1
  ORDER BY variant_count DESC
  LIMIT 10
""")

if normalization_check.num_rows == 0 do
  IO.puts("✅ No URL normalization issues detected")
else
  IO.puts("⚠️  Found #{normalization_check.num_rows} potential normalization issues:\n")

  Enum.each(normalization_check.rows, fn [norm_source, norm_target, count, variants] ->
    IO.puts("   • #{count} variants:")
    IO.puts("     Normalized: #{String.slice(norm_source, 0..80)}")
    IO.puts("     Variants: #{String.slice(variants, 0..120)}")
    IO.puts("")
  end)
end

# Summary
IO.puts("""

╔══════════════════════════════════════════════════════════╗
║  Summary                                                  ║
╚══════════════════════════════════════════════════════════╝

""")

total_backlinks = Repo.query!("SELECT COUNT(*) FROM backlinks")
total_count = total_backlinks.rows |> List.first() |> List.first()

unique_pairs = Repo.query!("SELECT COUNT(DISTINCT (source_url, target_url)) FROM backlinks")
unique_count = unique_pairs.rows |> List.first() |> List.first()

IO.puts("📊 Total backlinks: #{total_count}")
IO.puts("📊 Unique (source_url, target_url) pairs: #{unique_count}")

if total_count == unique_count do
  IO.puts("\n✅ RESULT: No duplicates exist in the database!")
  IO.puts("   What you see in the dashboard is multiple pages from the same domain")
  IO.puts("   linking to your content - these are VALID distinct backlinks.")
else
  IO.puts("\n⚠️  RESULT: #{total_count - unique_count} duplicate records found!")
  IO.puts("   The unique constraint may not be working as expected.")
end

IO.puts("")
