# Verify backlink import quality
alias GscAnalytics.Repo

IO.puts("\n📊 Verifying backlink import...\n")

# Check source_domain extraction
result = Repo.query!("""
  SELECT
    COUNT(*) as total,
    COUNT(DISTINCT source_domain) as unique_domains,
    COUNT(CASE WHEN source_domain IS NULL THEN 1 END) as null_domains
  FROM backlinks
""", [])

[total, unique_domains, null_domains] = result.rows |> List.first()

IO.puts("✅ Total backlinks: #{total}")
IO.puts("✅ Unique source domains: #{unique_domains}")
IO.puts("⚠️  NULL source_domains: #{null_domains}\n")

# Sample backlinks
IO.puts("Sample backlinks:\n")

sample = Repo.query!("""
  SELECT
    source_domain,
    anchor_text,
    data_source,
    SUBSTRING(source_url, 1, 60) as url_preview
  FROM backlinks
  ORDER BY RANDOM()
  LIMIT 10
""", [])

Enum.each(sample.rows, fn [domain, anchor, source, url] ->
  IO.puts("  • #{domain}")
  IO.puts("    Anchor: \"#{String.slice(anchor || "-", 0..50)}\"")
  IO.puts("    Source: #{source}")
  IO.puts("    URL: #{url}")
  IO.puts("")
end)

# Check for broken anchor texts (very short or containing quotes)
IO.puts("\n🔍 Checking for potentially broken anchor texts...\n")

broken = Repo.query!("""
  SELECT
    source_domain,
    anchor_text,
    data_source
  FROM backlinks
  WHERE LENGTH(anchor_text) < 5
     OR anchor_text LIKE '%"%'
     OR anchor_text LIKE '%,%'
  LIMIT 10
""", [])

if broken.num_rows == 0 do
  IO.puts("✅ No obviously broken anchor texts found!")
else
  IO.puts("⚠️  Found #{broken.num_rows} potentially broken anchor texts:\n")

  Enum.each(broken.rows, fn [domain, anchor, source] ->
    IO.puts("  • #{domain}")
    IO.puts("    Anchor: \"#{anchor}\"")
    IO.puts("    Source: #{source}")
    IO.puts("")
  end)
end
