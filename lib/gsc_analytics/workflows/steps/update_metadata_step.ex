defmodule GscAnalytics.Workflows.Steps.UpdateMetadataStep do
  @moduledoc """
  Updates URL metadata fields for URLs identified in previous steps.

  ## Configuration

  ```elixir
  %{
    "type" => "update_metadata",
    "config" => %{
      "source_step" => "step_1",  # Step ID containing URLs
      "updates" => %{
        "content_category" => "Aging",
        "last_update_date" => "2025-11-10"
      }
    }
  }
  ```

  ## Input Requirements

  Expects the source step output to contain:
  - `urls`: List of URL strings to update

  ## Output

  Returns a map with:
  - `updated_count`: Number of records updated
  - `urls_updated`: List of URLs that were updated
  - `skipped_count`: Number of URLs not found in metadata table

  ## Note

  Only updates fields that exist in the gsc_url_metadata table:
  - url_type, content_category, publish_date, last_update_date
  - title, meta_description, word_count
  - internal_links_count, external_links_count, last_crawled_at
  """

  alias GscAnalytics.{Repo, Schemas.UrlMetadata}
  import Ecto.Query
  require Logger

  @doc """
  Updates metadata for URLs from a previous step's output.
  """
  def execute(step_config, context, account_id) do
    source_step = get_in(step_config, ["config", "source_step"])
    updates = get_in(step_config, ["config", "updates"]) || %{}

    # Get URLs from source step output
    urls = get_urls_from_context(context, source_step)

    if Enum.empty?(urls) do
      {:ok,
       %{
         "updated_count" => 0,
         "urls_updated" => [],
         "skipped_count" => 0,
         "message" => "No URLs to update"
       }}
    else
      perform_updates(urls, updates, account_id)
    end
  end

  defp get_urls_from_context(context, source_step) do
    case get_in(context, ["variables", source_step, "output", "urls"]) do
      urls when is_list(urls) -> urls
      _ -> []
    end
  end

  defp perform_updates(urls, updates, account_id) do
    # Convert string keys to atoms for Ecto
    ecto_updates =
      updates
      |> Enum.map(fn {key, value} ->
        {String.to_existing_atom(key), value}
      end)
      |> Enum.into(%{})
      |> Map.put(:updated_at, DateTime.utc_now())

    # Find existing metadata records
    existing_urls =
      from(m in UrlMetadata,
        where: m.account_id == ^account_id,
        where: m.url in ^urls,
        select: m.url
      )
      |> Repo.all()

    # Update existing records
    {updated_count, _} =
      from(m in UrlMetadata,
        where: m.account_id == ^account_id,
        where: m.url in ^existing_urls
      )
      |> Repo.update_all(set: Enum.to_list(ecto_updates))

    # Create records for URLs that don't have metadata yet
    missing_urls = urls -- existing_urls
    created_count = create_missing_metadata(missing_urls, updates, account_id)

    total_updated = updated_count + created_count
    skipped_count = length(urls) - total_updated

    Logger.info(
      "UpdateMetadataStep: Updated #{updated_count}, created #{created_count}, skipped #{skipped_count}"
    )

    {:ok,
     %{
       "updated_count" => total_updated,
       "urls_updated" => existing_urls ++ missing_urls,
       "skipped_count" => skipped_count,
       "details" => %{
         "existing_updated" => updated_count,
         "new_created" => created_count
       }
     }}
  end

  defp create_missing_metadata([], _updates, _account_id), do: 0

  defp create_missing_metadata(urls, updates, account_id) do
    now = DateTime.utc_now()

    records =
      Enum.map(urls, fn url ->
        %{
          account_id: account_id,
          url: url,
          needs_update: updates["needs_update"],
          update_priority: updates["update_priority"],
          update_reason: updates["update_reason"],
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(UrlMetadata, records) do
      {count, _} -> count
      _ -> 0
    end
  end
end
