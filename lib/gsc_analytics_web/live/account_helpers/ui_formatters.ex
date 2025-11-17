defmodule GscAnalyticsWeb.Live.AccountHelpers.UIFormatters do
  @moduledoc """
  Display label formatting for accounts and properties.

  This module provides consistent formatting of:
  - Property URLs (extracting clean domain names)
  - Account labels (prioritizing OAuth email over display name)
  - Dropdown options for UI components

  ## Design Philosophy

  - **User-friendly**: Extract clean domain names from technical URLs
  - **Fallback chain**: Try multiple fields before defaulting to IDs
  - **Consistent**: Same formatting logic across all LiveViews
  """

  @doc """
  Extract a clean display label from a property URL.

  Handles both domain properties and URL-prefix properties.

  ## Examples

      iex> UIFormatters.extract_domain("sc-domain:example.com")
      "example.com"

      iex> UIFormatters.extract_domain("https://example.com/")
      "example.com"

      iex> UIFormatters.extract_domain("https://example.com/blog/")
      "example.com"
  """
  @spec extract_domain(String.t()) :: String.t()
  def extract_domain("sc-domain:" <> domain), do: String.trim(domain)

  def extract_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> url
    end
  end

  @doc """
  Format an account label for display.

  Priority order:
  1. OAuth Google email (most accurate, reflects current connection)
  2. Display name (user-configured)
  3. Account name (legacy field)
  4. Fallback to "Workspace {id}"

  ## Examples

      iex> account = %{id: 1, oauth: %{google_email: "user@example.com"}}
      iex> UIFormatters.format_account_label(account)
      "user@example.com"

      iex> account = %{id: 1, display_name: "My Workspace"}
      iex> UIFormatters.format_account_label(account)
      "My Workspace"

      iex> account = %{id: 1}
      iex> UIFormatters.format_account_label(account)
      "Workspace 1"
  """
  @spec format_account_label(map()) :: String.t()
  def format_account_label(account) do
    cond do
      # Use OAuth email as first priority
      Map.get(account, :oauth) && account.oauth.google_email ->
        account.oauth.google_email

      # Fall back to display_name if set
      Map.get(account, :display_name) && String.trim(account.display_name) != "" ->
        String.trim(account.display_name)

      # Then try the configured name
      Map.get(account, :name) && String.trim(account.name) != "" ->
        String.trim(account.name)

      true ->
        "Workspace #{account.id}"
    end
  end

  @doc """
  Format a property label for display.

  Extracts clean domain from property URL.

  ## Examples

      iex> property = %{property_url: "sc-domain:example.com"}
      iex> UIFormatters.format_property_label(property)
      "example.com"

      iex> property = %{property_url: "https://blog.example.com/"}
      iex> UIFormatters.format_property_label(property)
      "blog.example.com"
  """
  @spec format_property_label(map()) :: String.t()
  def format_property_label(property) do
    property_url = extract_property_url(property)
    extract_domain(property_url)
  end

  @doc """
  Build property dropdown options from properties grouped by account.

  Returns a list of property option maps with:
  - `:id` - Property ID
  - `:label` - Formatted domain name
  - `:favicon_url` - Optional favicon URL

  Options are sorted by account label alphabetically.

  ## Examples

      iex> properties_by_account = %{1 => [prop1, prop2], 2 => [prop3]}
      iex> accounts_by_id = %{1 => account1, 2 => account2}
      iex> UIFormatters.build_property_options(properties_by_account, accounts_by_id)
      [
        %{id: "prop1_id", label: "example.com", favicon_url: nil},
        %{id: "prop2_id", label: "test.com", favicon_url: "https://..."}
      ]
  """
  @spec build_property_options(map(), map()) :: list(map())
  def build_property_options(properties_by_account, accounts_by_id) do
    properties_by_account
    |> Enum.sort_by(fn {account_id, _props} ->
      account = Map.get(accounts_by_id, account_id)
      label = format_account_label_with_id(account, account_id)
      {String.downcase(label), account_id}
    end)
    |> Enum.flat_map(fn {_account_id, properties} ->
      Enum.map(properties, fn property ->
        property_label = format_property_label(property)
        favicon_url = Map.get(property, :favicon_url)

        %{
          label: property_label,
          id: property.id,
          favicon_url: favicon_url
        }
      end)
    end)
  end

  @doc """
  Build property lookup map for quick property-to-account resolution.

  Returns a map of `property_id => %{account_id: id, property: property}`.

  ## Examples

      iex> properties_by_account = %{1 => [prop1], 2 => [prop2]}
      iex> UIFormatters.build_property_lookup(properties_by_account)
      %{
        "prop1_id" => %{account_id: 1, property: prop1},
        "prop2_id" => %{account_id: 2, property: prop2}
      }
  """
  @spec build_property_lookup(map()) :: map()
  def build_property_lookup(properties_by_account) do
    Enum.reduce(properties_by_account, %{}, fn {account_id, properties}, acc ->
      Enum.reduce(properties, acc, fn property, lookup ->
        Map.put(lookup, property.id, %{account_id: account_id, property: property})
      end)
    end)
  end

  # ---------------------------------------------------------------------------
  # Private Helpers
  # ---------------------------------------------------------------------------

  defp extract_property_url(%{property_url: property_url}) when is_binary(property_url) do
    String.trim(property_url)
  end

  defp extract_property_url(_property), do: "Property"

  defp format_account_label_with_id(nil, account_id), do: "Workspace #{account_id}"

  defp format_account_label_with_id(account, account_id) do
    cond do
      # Use OAuth email as first priority
      Map.get(account, :oauth) && account.oauth.google_email ->
        account.oauth.google_email

      # Fall back to display_name if set
      Map.get(account, :display_name) && String.trim(account.display_name) != "" ->
        String.trim(account.display_name)

      # Then try the configured name
      Map.get(account, :name) && String.trim(account.name) != "" ->
        String.trim(account.name)

      true ->
        "Workspace #{account_id}"
    end
  end
end
