defmodule Mix.Tasks.Phase4.Rollout do
  @moduledoc """
  Helper task that automates the Phase 4 rollout drills.

  Runs a sequential baseline (max_concurrency: 1) followed by a concurrent run
  using the requested concurrency/queue/backpressure values. Outputs a Markdown
  summary that can be pasted directly into the rollout playbook.
  """
  use Mix.Task

  alias GscAnalytics.DataSources.GSC.Core.{Config, Sync}

  @shortdoc "Runs sequential + concurrent syncs and emits a rollout summary"

  @switches [
    site_url: :string,
    account_id: :integer,
    days: :integer,
    concurrency: :integer,
    queue_size: :integer,
    in_flight: :integer,
    output: :string,
    force: :boolean,
    keep_auto_sync: :boolean
  ]

  @impl true
  def run(args) do
    opts =
      args
      |> OptionParser.parse!(switches: @switches)
      |> elem(0)
      |> normalize_options()

    env_guard =
      if opts.disable_auto_sync? do
        disable_auto_sync()
      else
        :noop
      end

    try do
      Mix.Task.run("app.start")

      if opts.disable_auto_sync? do
        Mix.shell().info("→ Auto-sync temporarily disabled for this run")
      end

      {start_date, end_date} = date_range(opts.days)
      Mix.shell().info("→ Date window: #{start_date} → #{end_date} (#{opts.days} days)")

      baseline =
        run_sync(
          :sequential,
          start_date,
          end_date,
          %{opts | concurrency: 1},
          "Sequential baseline"
        )

      concurrent =
        run_sync(:concurrent, start_date, end_date, opts, "Concurrent run (#{opts.concurrency}×)")

      summary = build_summary(opts, start_date, end_date, baseline, concurrent)
      write_summary(opts.output_path, summary)

      Mix.shell().info("✅ Phase 4 rollout summary written to #{opts.output_path}")
    after
      restore_auto_sync(env_guard)
    end
  end

  defp normalize_options(opts) do
    site_url =
      opts[:site_url] ||
        Mix.raise("""
        Missing --site-url option.
        Example:
          mix phase4.rollout --site-url "sc-domain:example.com" --account-id 4
        """)

    %{
      site_url: site_url,
      account_id: opts[:account_id] || Config.default_account_id(),
      days: opts[:days] || 150,
      concurrency: opts[:concurrency] || Config.max_concurrency(),
      queue_size: opts[:queue_size] || Config.max_queue_size(),
      in_flight: opts[:in_flight] || Config.max_in_flight(),
      output_path: opts[:output] || default_output_path(),
      force?: Keyword.get(opts, :force, true),
      disable_auto_sync?: Keyword.get(opts, :keep_auto_sync, false) != true
    }
  end

  defp date_range(days) do
    end_date = Date.add(Date.utc_today(), -Config.data_delay_days())
    start_date = Date.add(end_date, -(days - 1))
    {start_date, end_date}
  end

  defp run_sync(label, start_date, end_date, opts, log_message) do
    Mix.shell().info("→ #{log_message} (max_concurrency=#{opts.concurrency})")

    overrides = %{
      max_concurrency: opts.concurrency,
      max_queue_size: opts.queue_size,
      max_in_flight: opts.in_flight
    }

    result =
      with_config(overrides, fn ->
        :timer.tc(fn ->
          Sync.sync_date_range(opts.site_url, start_date, end_date,
            account_id: opts.account_id,
            force?: opts.force?
          )
        end)
      end)

    format_run_result(label, result)
  end

  defp format_run_result(label, {duration_us, {:ok, summary}}) do
    %{
      label: label,
      duration_ms: div(duration_us, 1_000),
      status: :ok,
      summary: summary
    }
  end

  defp format_run_result(label, {duration_us, other}) do
    %{
      label: label,
      duration_ms: div(duration_us, 1_000),
      status: {:error, other},
      summary: %{}
    }
  end

  defp build_summary(opts, start_date, end_date, baseline, concurrent) do
    speedup =
      if baseline.duration_ms > 0 and concurrent.duration_ms > 0 do
        Float.round(baseline.duration_ms / concurrent.duration_ms, 2)
      else
        "n/a"
      end

    """
    # Phase 4 Rollout Snapshot (#{timestamp()})

    * Site URL: #{opts.site_url}
    * Account ID: #{opts.account_id}
    * Date Range: #{start_date} → #{end_date} (#{opts.days} days)
    * Queue / In-Flight Limits: #{opts.queue_size} queue / #{opts.in_flight} in-flight

    | Mode | Max Concurrency | Duration (ms) | API Calls | Query Rows | Status |
    |------|-----------------|---------------|-----------|------------|--------|
    #{table_row("Sequential baseline", 1, baseline)}
    #{table_row("Concurrent (#{opts.concurrency}×)", opts.concurrency, concurrent)}

    **Speedup**: #{speedup}×
    """
  end

  defp table_row(label, concurrency, %{duration_ms: duration, status: status, summary: summary}) do
    api_calls = summary[:api_calls] || "-"
    total_queries = summary[:total_queries] || "-"
    status_label = format_status(status)

    "| #{label} | #{concurrency} | #{duration} | #{api_calls} | #{total_queries} | #{status_label} |"
  end

  defp format_status(:ok), do: "✅ ok"
  defp format_status({:error, reason}), do: "⚠️ #{inspect(reason)}"
  defp format_status(other), do: inspect(other)

  defp write_summary(path, content) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
  end

  defp default_output_path do
    Path.join(["output", "phase4_rollout_" <> timestamp() <> ".md"])
  end

  defp timestamp do
    DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d_%H-%M-%S")
  end

  defp with_config(overrides, fun) do
    original = Application.get_env(:gsc_analytics, Config)

    new_config =
      (original || [])
      |> Keyword.put(:max_concurrency, overrides.max_concurrency)
      |> Keyword.put(:max_queue_size, overrides.max_queue_size)
      |> Keyword.put(:max_in_flight, overrides.max_in_flight)

    Application.put_env(:gsc_analytics, Config, new_config)

    try do
      fun.()
    after
      if original == nil do
        Application.delete_env(:gsc_analytics, Config)
      else
        Application.put_env(:gsc_analytics, Config, original)
      end
    end
  end

  defp disable_auto_sync do
    original = System.get_env("ENABLE_AUTO_SYNC")
    System.put_env("ENABLE_AUTO_SYNC", "false")
    original || :unset
  end

  defp restore_auto_sync(:noop), do: :ok

  defp restore_auto_sync(:unset) do
    System.delete_env("ENABLE_AUTO_SYNC")
  end

  defp restore_auto_sync(value) when is_binary(value) do
    System.put_env("ENABLE_AUTO_SYNC", value)
  end
end
