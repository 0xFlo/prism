defmodule GscAnalytics.Workers.HttpStatusCheckWorkerTest do
  use GscAnalytics.DataCase, async: true
  use Oban.Testing, repo: GscAnalytics.Repo

  import GscAnalytics.AccountsFixtures

  alias GscAnalytics.Workers.HttpStatusCheckWorker
  alias GscAnalytics.Schemas.Performance

  describe "enqueue_urls/2" do
    test "enqueues HTTP status check jobs for provided URLs" do
      workspace = workspace_fixture()
      account_id = workspace.id

      urls = [
        %{
          account_id: account_id,
          property_url: "sc-domain:example.com",
          url: "https://example.com/page1"
        },
        %{
          account_id: account_id,
          property_url: "sc-domain:example.com",
          url: "https://example.com/page2"
        }
      ]

      {:ok, jobs} = HttpStatusCheckWorker.enqueue_urls(urls)

      assert length(jobs) == 1
      assert {:ok, %Oban.Job{}} = List.first(jobs)

      # Verify job is queued
      assert_enqueued(worker: HttpStatusCheckWorker, queue: :http_checks)
    end

    test "splits large URL lists into multiple jobs" do
      workspace = workspace_fixture()
      account_id = workspace.id

      # Create 150 URLs (should be split into 3 batches of 50)
      urls =
        Enum.map(1..150, fn i ->
          %{
            account_id: account_id,
            property_url: "sc-domain:example.com",
            url: "https://example.com/page#{i}"
          }
        end)

      {:ok, jobs} = HttpStatusCheckWorker.enqueue_urls(urls)

      # Should create 3 jobs (150 URLs / 50 batch size)
      assert length(jobs) == 3
    end

    test "returns {:ok, []} when no URLs provided" do
      assert {:ok, []} = HttpStatusCheckWorker.enqueue_urls([])
    end
  end

  describe "enqueue_new_urls/1" do
    test "enqueues only unchecked URLs" do
      workspace = workspace_fixture()
      account_id = workspace.id
      property_url = "sc-domain:example.com"

      # Create Performance records - one checked, one unchecked
      checked_url = "https://example.com/checked"
      unchecked_url = "https://example.com/unchecked"

      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: checked_url,
        http_status: 200,
        http_checked_at: DateTime.utc_now(),
        data_available: true
      })
      |> Repo.insert!()

      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: unchecked_url,
        data_available: true
      })
      |> Repo.insert!()

      {:ok, jobs} =
        HttpStatusCheckWorker.enqueue_new_urls(
          account_id: account_id,
          property_url: property_url,
          urls: [checked_url, unchecked_url]
        )

      # Should only enqueue 1 job for the unchecked URL
      assert length(jobs) == 1

      # Verify the job contains only the unchecked URL
      assert_enqueued(
        worker: HttpStatusCheckWorker,
        queue: :http_checks,
        args: %{
          "urls" => [
            %{
              "account_id" => account_id,
              "property_url" => property_url,
              "url" => unchecked_url
            }
          ]
        }
      )
    end

    test "returns {:ok, []} when all URLs are already checked" do
      workspace = workspace_fixture()
      account_id = workspace.id
      property_url = "sc-domain:example.com"
      url = "https://example.com/page"

      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: url,
        http_status: 200,
        http_checked_at: DateTime.utc_now(),
        data_available: true
      })
      |> Repo.insert!()

      assert {:ok, []} =
               HttpStatusCheckWorker.enqueue_new_urls(
                 account_id: account_id,
                 property_url: property_url,
                 urls: [url]
               )
    end
  end

  describe "enqueue_stale_urls/1" do
    test "enqueues stale URLs for checking" do
      workspace = workspace_fixture()
      account_id = workspace.id
      property_url = "sc-domain:example.com"

      # Create stale URL (checked 30 days ago)
      thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: "https://example.com/stale",
        http_status: 200,
        http_checked_at: thirty_days_ago,
        data_available: true
      })
      |> Repo.insert!()

      {:ok, jobs} =
        HttpStatusCheckWorker.enqueue_stale_urls(
          account_id: account_id,
          property_url: property_url
        )

      assert length(jobs) == 1
      assert_enqueued(worker: HttpStatusCheckWorker, queue: :http_checks)
    end

    test "prioritizes never-checked and error URLs" do
      workspace = workspace_fixture()
      account_id = workspace.id
      property_url = "sc-domain:example.com"

      # Create never-checked URL
      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: "https://example.com/never-checked",
        data_available: true
      })
      |> Repo.insert!()

      # Create error URL (404 checked 5 days ago)
      five_days_ago = DateTime.utc_now() |> DateTime.add(-5, :day)

      %Performance{}
      |> Performance.changeset(%{
        account_id: account_id,
        property_url: property_url,
        url: "https://example.com/broken",
        http_status: 404,
        http_checked_at: five_days_ago,
        data_available: true
      })
      |> Repo.insert!()

      {:ok, _jobs} =
        HttpStatusCheckWorker.enqueue_stale_urls(
          account_id: account_id,
          property_url: property_url
        )

      # Should enqueue both URLs
      assert_enqueued(worker: HttpStatusCheckWorker, queue: :http_checks)
    end

    test "returns {:ok, []} when no stale URLs exist" do
      workspace = workspace_fixture()
      account_id = workspace.id

      assert {:ok, []} =
               HttpStatusCheckWorker.enqueue_stale_urls(
                 account_id: account_id,
                 property_url: "sc-domain:example.com"
               )
    end
  end
end
