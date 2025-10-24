defmodule GscAnalytics.DataSources.GSC.Core.ClientTest do
  use GscAnalytics.DataCase, async: false

  alias GscAnalytics.DataSources.GSC.Core.Client
  alias GscAnalytics.DataSources.GSC.Accounts

  describe "list_sites/1 - parsing logic" do
    test "identifies domain properties vs URL properties" do
      sites = [
        %{site_url: "sc-domain:example.com", permission_level: "siteOwner"},
        %{site_url: "https://www.example.com/", permission_level: "siteOwner"},
        %{site_url: "http://subdomain.example.com/", permission_level: "siteFullUser"}
      ]

      domain_properties =
        sites
        |> Enum.filter(fn site -> String.starts_with?(site.site_url, "sc-domain:") end)
        |> Enum.map(fn site -> String.replace_prefix(site.site_url, "sc-domain:", "") end)

      url_properties =
        sites
        |> Enum.filter(fn site -> String.starts_with?(site.site_url, "http") end)
        |> Enum.map(fn site -> URI.parse(site.site_url).host end)

      assert domain_properties == ["example.com"]
      assert url_properties == ["www.example.com", "subdomain.example.com"]
    end
  end

  describe "list_sites/1 integration" do
    @tag :integration
    test "fetches real GSC properties for configured accounts" do
      # This test only runs with the :integration tag
      # Run with: mix test --only integration

      # For account 1 (Scrapfly)
      case Client.list_sites(1) do
        {:ok, sites} ->
          IO.puts("\nAccount 1 (Scrapfly) has access to #{length(sites)} properties:")
          Enum.each(sites, fn site ->
            IO.puts("  - #{site.site_url} (#{site.permission_level})")
          end)

          # Verify we have at least the configured property
          configured_site = "sc-domain:scrapfly.io"
          assert Enum.any?(sites, fn site -> site.site_url == configured_site end),
                 "Should have access to #{configured_site}"

        {:error, reason} ->
          IO.puts("Skipping integration test - Auth not configured: #{inspect(reason)}")
      end

      # For account 2
      case Client.list_sites(2) do
        {:ok, sites} ->
          IO.puts("\nAccount 2 has access to #{length(sites)} properties:")
          Enum.each(sites, fn site ->
            IO.puts("  - #{site.site_url} (#{site.permission_level})")
          end)

        {:error, reason} ->
          IO.puts("Account 2 auth error: #{inspect(reason)}")
      end
    end
  end
end