# Claude Code SDK Integration Guide

This repository runs in a sandbox without outbound network access, so the SDK
cannot be installed directly here. The steps below document how to configure
Anthropic's Claude Code SDK on a developer workstation so the high-intent
content detector (or any other tooling) can call Claude for deeper analysis
when you have network access.

## 1. Install Dependencies

```bash
# Using pip (recommended)
pip install anthropic python-dotenv

# or with uv
uv pip install anthropic python-dotenv
```

These packages provide the Claude SDK plus `.env` helpers for keeping your API
key out of source control.

## 2. Configure Environment Variables

Create a `.env` file (excluded from git) and add:

```bash
ANTHROPIC_API_KEY=your_api_key_here
CLAUDE_MODEL=claude-3-5-sonnet-20241022
```

Load it in shells that launch Mix tasks or IEx sessions:

```bash
export $(grep -v '^#' .env | xargs)
```

## 3. Optional: Mix Task Wrapper

Add a small Mix task (example only – do **not** commit secrets):

```elixir
# lib/mix/tasks/claude.ask.ex
Mix.Task.start_link(:app)

defmodule Mix.Tasks.Claude.Ask do
  use Mix.Task

  def run([prompt | _]) do
    {:ok, client} = Anthropic.Client.new(api_key: System.fetch_env!("ANTHROPIC_API_KEY"))

    {:ok, response} =
      Anthropic.Messages.create(client, %{
        model: System.get_env("CLAUDE_MODEL", "claude-3-5-sonnet-20241022"),
        max_tokens: 1024,
        messages: [%{role: :user, content: prompt}]
      })

    IO.inspect(response)
  end
end
```

Run it with:

```bash
mix claude.ask "Summarise high-intent URLs"
```

## 4. Usage With High-Intent Detector

You can pipe the CSV emitted by `HighIntentContent.to_csv/1` into Claude for
further clustering, scoring, or content refresh suggestions.

1. Generate the CSV locally:
   ```bash
   elixir -r lib/gsc_analytics/analysis/high_intent_content.ex \
          -e 'posts = GscAnalytics.Analysis.HighIntentContent.list_high_intent_posts();
               IO.puts(GscAnalytics.Analysis.HighIntentContent.to_csv(posts))' > high_intent.csv
   ```
2. Feed relevant rows into Claude using the Mix task above or any notebook.

## 5. Safety Notes

- Never commit API keys; rely on env vars or secret managers.
- Review Anthropic usage policies before automating content generation.
- Keep SDK calls behind feature flags so production sync jobs remain stable if
  the API is unavailable.
```

