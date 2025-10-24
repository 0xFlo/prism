# Verify DR and domain traffic import
alias GscAnalytics.Repo

IO.puts("\n📊 Verifying DR and domain traffic import...\n")

# Check distribution of DR and traffic
stats = Repo.query!("""
  SELECT
    data_source,
    COUNT(*) as total,
    COUNT(domain_rating) as with_dr,
    COUNT(domain_traffic) as with_traffic,
    AVG(domain_rating) as avg_dr,
    AVG(domain_traffic) as avg_traffic,
    MAX(domain_rating) as max_dr,
    MAX(domain_traffic) as max_traffic
  FROM backlinks
  GROUP BY data_source
  ORDER BY data_source
""", [])

IO.puts("Distribution by source:\n")

Enum.each(stats.rows, fn [source, total, with_dr, with_traffic, avg_dr, avg_traffic, max_dr, max_traffic] ->
  IO.puts("  📌 #{source}:")
  IO.puts("     Total: #{total} backlinks")
  IO.puts("     With DR: #{with_dr} (#{Float.round(with_dr / total * 100, 1)}%)")
  IO.puts("     With Traffic: #{with_traffic} (#{Float.round(with_traffic / total * 100, 1)}%)")

  if avg_dr do
    avg_dr_float = if is_struct(avg_dr, Decimal), do: Decimal.to_float(avg_dr), else: avg_dr
    IO.puts("     Avg DR: #{Float.round(avg_dr_float, 1)} (max: #{max_dr})")
  end

  if avg_traffic do
    avg_traffic_float = if is_struct(avg_traffic, Decimal), do: Decimal.to_float(avg_traffic), else: avg_traffic
    IO.puts("     Avg Traffic: #{Float.round(avg_traffic_float, 0)} (max: #{max_traffic})")
  end

  IO.puts("")
end)

# Sample high-DR backlinks
IO.puts("\n🏆 Top 10 backlinks by Domain Rating:\n")

top_dr = Repo.query!("""
  SELECT
    source_domain,
    domain_rating,
    domain_traffic,
    anchor_text,
    data_source
  FROM backlinks
  WHERE domain_rating IS NOT NULL
  ORDER BY domain_rating DESC
  LIMIT 10
""", [])

Enum.each(top_dr.rows, fn [domain, dr, traffic, anchor, source] ->
  IO.puts("  • #{domain}")
  IO.puts("    DR: #{dr} | Traffic: #{traffic || "N/A"} | Source: #{source}")
  IO.puts("    Anchor: \"#{String.slice(anchor || "-", 0..50)}\"")
  IO.puts("")
end)
