defmodule Signal.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :stream_id, :string, null: false
      add :event_type, :string, null: false
      add :payload, :jsonb, null: false
      add :version, :integer, null: false
      add :timestamp, :timestamptz, null: false, default: fragment("NOW()")
    end

    # Unique constraint on (stream_id, version) for optimistic locking
    create unique_index(:events, [:stream_id, :version])

    # Index for querying by event type
    create index(:events, [:event_type])

    # Index for time-based queries
    create index(:events, [:timestamp])
  end
end
