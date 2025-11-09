defmodule GscAnalytics.Repo.Migrations.CreateWorkflows do
  use Ecto.Migration

  def change do
    # Workflows table - stores workflow definitions (blueprints)
    create table(:workflows, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"

      # JSON field storing step graph structure
      add :definition, :map, null: false

      # Input schema definition (for validation)
      add :input_schema, :map

      # Workflow metadata
      add :tags, {:array, :string}, default: []
      add :version, :integer, default: 1
      add :published_at, :utc_datetime

      # Foreign keys
      add :account_id, references(:workspaces, on_delete: :delete_all)
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Indexes optimized per Codex review
    create index(:workflows, [:account_id])
    create index(:workflows, [:status])
    create index(:workflows, [:created_by_id])
    # Composite index for LiveView streams pagination
    create index(:workflows, [:account_id, :inserted_at])
    create index(:workflows, [:status, :inserted_at])

    # Workflow Executions table - runtime instances
    create table(:workflow_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "queued"

      # Input data provided at execution time
      add :input_data, :map

      # Final output (populated on completion)
      add :output_data, :map

      # Current variable context (Note: This is redundant with ETS runtime state,
      # but serves as checkpoint for crash recovery)
      add :context_snapshot, :map, default: %{}

      # Runtime metrics
      add :current_step_id, :string
      add :completed_step_ids, {:array, :string}, default: []
      add :failed_step_ids, {:array, :string}, default: []

      # Timestamps
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :paused_at, :utc_datetime

      # Error tracking
      add :error_message, :text
      add :error_step_id, :string

      # Foreign keys
      add :workflow_id, references(:workflows, type: :binary_id, on_delete: :delete_all)
      add :account_id, references(:workspaces, on_delete: :delete_all)
      add :triggered_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Indexes optimized per Codex review
    create index(:workflow_executions, [:workflow_id])
    create index(:workflow_executions, [:account_id])
    create index(:workflow_executions, [:status])
    create index(:workflow_executions, [:started_at])
    # Composite indexes for efficient LiveView queries
    create index(:workflow_executions, [:workflow_id, :inserted_at])
    create index(:workflow_executions, [:id, :status])
    create index(:workflow_executions, [:account_id, :status, :inserted_at])
    # JSON index for frequently queried context fields (Postgres only)
    execute "CREATE INDEX workflow_executions_context_gin_idx ON workflow_executions USING GIN (context_snapshot)",
            "DROP INDEX workflow_executions_context_gin_idx"

    # Workflow Execution Events table - immutable audit log
    create table(:workflow_execution_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :step_id, :string
      add :step_type, :string

      # Event-specific data (e.g., step output, error details)
      add :payload, :map

      # Duration for completed steps
      add :duration_ms, :integer

      # Foreign key
      add :execution_id,
          references(:workflow_executions, type: :binary_id, on_delete: :delete_all)

      # Only inserted_at (immutable event stream)
      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Indexes optimized per Codex review
    create index(:workflow_execution_events, [:execution_id])
    create index(:workflow_execution_events, [:event_type])
    create index(:workflow_execution_events, [:inserted_at])
    # Composite index for event timeline queries
    create index(:workflow_execution_events, [:execution_id, :inserted_at])
    # JSON index for event payloads (Postgres only)
    execute "CREATE INDEX workflow_execution_events_payload_gin_idx ON workflow_execution_events USING GIN (payload)",
            "DROP INDEX workflow_execution_events_payload_gin_idx"

    # Workflow Review Queue table - human review items
    create table(:workflow_review_queue, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :step_id, :string
      add :prompt_text, :text
      add :context_data, :map

      # Review decision
      add :reviewed_at, :utc_datetime
      add :review_notes, :text
      add :expires_at, :utc_datetime

      # Foreign keys
      add :execution_id,
          references(:workflow_executions, type: :binary_id, on_delete: :delete_all)

      add :reviewer_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # Indexes optimized per Codex review
    create index(:workflow_review_queue, [:execution_id])
    create index(:workflow_review_queue, [:status])
    create index(:workflow_review_queue, [:reviewer_id])
    create index(:workflow_review_queue, [:expires_at])
    # Composite index for pending reviews dashboard
    create index(:workflow_review_queue, [:status, :inserted_at])
    # Materialized aggregate for pending count
    # Note: Consider implementing via database view or Oban metadata
  end
end
