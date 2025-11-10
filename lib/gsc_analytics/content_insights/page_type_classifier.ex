defmodule GscAnalytics.ContentInsights.PageTypeClassifier do
  @moduledoc """
  Infers page types from URL structure using a hybrid classification approach.

  Combines multiple strategies for accurate categorization:
  - Path-based detection (matches /blog/, /docs/, /products/)
  - Pattern matching (date patterns, SKU patterns, etc.)
  - Depth analysis (homepage, category, detail pages)

  ## Supported Page Types

  - `:homepage` - Root path (/)
  - `:blog` - Blog posts and articles
  - `:documentation` - Help, docs, guides
  - `:product` - Product pages and e-commerce
  - `:category` - Top-level category/section pages
  - `:landing` - Landing pages and promotional content
  - `:legal` - Terms, privacy, legal pages
  - `:other` - Unmatched URLs (fallback)

  ## Examples

      iex> classify("https://example.com/")
      :homepage

      iex> classify("https://example.com/blog/my-post")
      :blog

      iex> classify("https://example.com/2024/01/15/article-title")
      :blog

      iex> classify("https://example.com/docs/getting-started")
      :documentation

      iex> classify("https://example.com/products/widget-123")
      :product

      iex> classify("https://example.com/electronics")
      :category
  """

  @doc """
  Classify a URL into a page type category.

  Returns an atom representing the inferred page type.
  """
  @spec classify(String.t()) :: atom()
  def classify(url) when is_binary(url) do
    uri = URI.parse(url)
    path = normalize_path(uri.path)

    cond do
      is_homepage?(path) -> :homepage
      is_blog?(path) -> :blog
      is_documentation?(path) -> :documentation
      is_product?(path) -> :product
      is_landing?(path) -> :landing
      is_legal?(path) -> :legal
      is_category?(path) -> :category
      true -> :other
    end
  end

  def classify(_invalid), do: :other

  @doc """
  Get all available page type categories.

  Returns a list of tuples with {atom, human_label} pairs.
  """
  @spec available_types() :: [{atom(), String.t()}]
  def available_types do
    [
      {:homepage, "Homepage"},
      {:blog, "Blog"},
      {:documentation, "Documentation"},
      {:product, "Product"},
      {:category, "Category"},
      {:landing, "Landing Page"},
      {:legal, "Legal"},
      {:other, "Other"}
    ]
  end

  @doc """
  Get human-readable label for a page type.
  """
  @spec label(atom()) :: String.t()
  def label(:homepage), do: "Homepage"
  def label(:blog), do: "Blog"
  def label(:documentation), do: "Documentation"
  def label(:product), do: "Product"
  def label(:category), do: "Category"
  def label(:landing), do: "Landing Page"
  def label(:legal), do: "Legal"
  def label(:other), do: "Other"
  def label(_), do: "Unknown"

  # Private classification functions

  defp normalize_path(nil), do: "/"
  defp normalize_path(""), do: "/"
  defp normalize_path(path), do: String.trim_trailing(path, "/")

  defp is_homepage?(path) when path in ["", "/"], do: true
  defp is_homepage?(_), do: false

  defp is_blog?(path) do
    # Path-based: starts with /blog/, /articles/, /posts/, /news/
    blog_paths = ["/blog", "/articles", "/posts", "/news", "/stories"]
    path_matches = Enum.any?(blog_paths, &String.starts_with?(path, &1))

    # Pattern-based: date pattern /YYYY/MM/DD/ or /YYYY/MM/
    date_pattern = ~r|^/\d{4}/\d{1,2}(/\d{1,2})?/|

    path_matches or Regex.match?(date_pattern, path)
  end

  defp is_documentation?(path) do
    doc_paths = ["/docs", "/documentation", "/help", "/guides", "/manual", "/wiki", "/kb"]
    Enum.any?(doc_paths, &String.starts_with?(path, &1))
  end

  defp is_product?(path) do
    # Path-based: starts with /products/, /shop/, /store/, /catalog/
    product_paths = ["/products", "/product", "/shop", "/store", "/catalog", "/item"]
    path_matches = Enum.any?(product_paths, &String.starts_with?(path, &1))

    # Pattern-based: SKU-like patterns (product-123, item-ABC-456)
    sku_pattern = ~r{/(product|item|sku)-[a-zA-Z0-9-]+}

    path_matches or Regex.match?(sku_pattern, path)
  end

  defp is_landing?(path) do
    landing_paths = ["/landing", "/lp", "/promo", "/campaign", "/special"]
    Enum.any?(landing_paths, &String.starts_with?(path, &1))
  end

  defp is_legal?(path) do
    # Exact matches or starts with /legal/
    legal_paths = [
      "/privacy",
      "/terms",
      "/tos",
      "/legal",
      "/cookie-policy",
      "/gdpr",
      "/disclaimer",
      "/refund",
      "/shipping"
    ]

    Enum.any?(legal_paths, fn legal_path ->
      path == legal_path or String.starts_with?(path, legal_path <> "/")
    end)
  end

  defp is_category?(path) do
    # Category pages are typically depth 1 (e.g., /electronics, /clothing)
    # Exclude if already matched other patterns
    segments = path |> String.split("/") |> Enum.reject(&(&1 == ""))

    # Exactly 1 segment and doesn't match other patterns
    length(segments) == 1
  end

  @doc """
  Compute page type count statistics for a list of URLs.

  Returns a map of page_type => count.

  ## Example

      iex> urls = ["https://example.com/", "https://example.com/blog/post1"]
      iex> count_by_type(urls)
      %{homepage: 1, blog: 1}
  """
  @spec count_by_type([String.t()]) :: %{atom() => non_neg_integer()}
  def count_by_type(urls) when is_list(urls) do
    urls
    |> Enum.map(&classify/1)
    |> Enum.frequencies()
  end
end
