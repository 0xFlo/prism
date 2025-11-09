defmodule GscAnalytics.Test.Fixtures.ScrapflyResponses do
  @moduledoc """
  Fixture responses from ScrapFly API for testing.

  These are realistic responses based on actual API behavior.
  Uses HTML parsing (no LLM extraction).
  """

  @doc """
  Successful SERP scrape - URL found at position 3.
  """
  def success_with_position do
    {:ok,
     %{
       status: 200,
       body: %{
         "result" => %{
           "content" => build_serp_html_with_target_at_position(3, "https://elixir-lang.org"),
           "status_code" => 200
         }
       }
     }}
  end

  # Build realistic Google SERP HTML with target URL at specified position
  defp build_serp_html_with_target_at_position(position, target_url) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Google Search Results</title></head>
    <body>
      <div id="search">
        #{build_organic_results(position, target_url)}
      </div>
    </body>
    </html>
    """
  end

  defp build_organic_results(target_position, target_url) do
    1..10
    |> Enum.map(fn pos ->
      url = if pos == target_position, do: target_url, else: "https://competitor#{pos}.com"

      title =
        if pos == target_position, do: "Elixir Programming Language", else: "Competitor #{pos}"

      """
      <div class="g">
        <div class="yuRUbf">
          <a href="#{url}">
            <h3>#{title}</h3>
          </a>
        </div>
        <div class="VwiC3b">Description for result #{pos}</div>
      </div>
      """
    end)
    |> Enum.join("\n")
  end

  @doc """
  Successful SERP scrape but target URL not found in results.
  """
  def success_url_not_found do
    {:ok,
     %{
       status: 200,
       body: %{
         "result" => %{
           "content" => build_serp_html_without_target(),
           "status_code" => 200
         }
       }
     }}
  end

  defp build_serp_html_without_target do
    """
    <!DOCTYPE html>
    <html>
    <head><title>Google Search Results</title></head>
    <body>
      <div id="search">
        <div class="g">
          <div class="yuRUbf">
            <a href="https://competitor1.com">
              <h3>Top Competitor Result</h3>
            </a>
          </div>
        </div>
        <div class="g">
          <div class="yuRUbf">
            <a href="https://competitor2.com">
              <h3>Second Competitor Result</h3>
            </a>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
  end

  @doc """
  ScrapFly API error response.
  """
  def api_error do
    {:ok,
     %{
       status: 200,
       body: %{
         "result" => %{
           "error" => "ERR::SCRAPE::FAILED",
           "error_description" => "Failed to fetch the target URL."
         }
       }
     }}
  end

  @doc """
  Rate limit exceeded (429 status).
  """
  def rate_limit_error do
    {:ok,
     %{
       status: 429,
       body: %{
         "error" => "rate_limit_exceeded",
         "message" => "You have exceeded your rate limit. Please retry after 60 seconds."
       }
     }}
  end

  @doc """
  Internal server error (500 status).
  """
  def internal_server_error do
    {:ok,
     %{
       status: 500,
       body: %{
         "error" => "internal_server_error",
         "message" => "An unexpected error occurred. Please contact support."
       }
     }}
  end

  @doc """
  Request timeout error (from Req library).
  """
  def timeout_error do
    {:error, %Req.TransportError{reason: :timeout}}
  end

  @doc """
  Malformed response missing content.
  """
  def malformed_response do
    {:ok,
     %{
       status: 200,
       body: %{
         "result" => %{
           "status_code" => 200
           # Missing content key
         }
       }
     }}
  end

  @doc """
  Invalid HTML response (not parseable).
  """
  def invalid_structure do
    {:ok,
     %{
       status: 200,
       body: %{
         "result" => %{
           "content" => "Not valid HTML at all, just plain text",
           "status_code" => 200
         }
       }
     }}
  end
end
