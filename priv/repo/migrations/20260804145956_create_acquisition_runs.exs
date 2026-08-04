defmodule SantoApi.Repo.Migrations.CreateAcquisitionRuns do
  use Ecto.Migration

  def change do
    create table(:acquisition_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :initiated_by_user_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :policy, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:acquisition_runs, [:vehicle_id, :inserted_at])
    create index(:acquisition_runs, [:initiated_by_user_id])
    create index(:acquisition_runs, [:status])

    create unique_index(:acquisition_runs, [:vehicle_id, :policy],
             where: "status IN ('pending', 'running')",
             name: :acquisition_runs_active_vehicle_policy_index
           )

    create constraint(:acquisition_runs, :acquisition_runs_valid_policy,
             check: "policy IN ('free_public_v1')"
           )

    create constraint(:acquisition_runs, :acquisition_runs_valid_status,
             check: "status IN ('pending', 'running', 'complete')"
           )

    create table(:acquisition_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :run_id,
          references(:acquisition_runs, type: :binary_id, on_delete: :restrict),
          null: false

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)
      add :step_key, :string, null: false
      add :position, :integer, null: false
      add :kind, :string, null: false
      add :provider, :string
      add :capability, :string, null: false
      add :status, :string, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :missing_selectors, {:array, :string}, null: false, default: []
      add :diagnostics, :map, null: false, default: %{}
      add :last_error, :map
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:acquisition_steps, [:run_id, :step_key])
    create unique_index(:acquisition_steps, [:run_id, :position])
    create index(:acquisition_steps, [:run_id, :status])
    create index(:acquisition_steps, [:artifact_id])

    create constraint(:acquisition_steps, :acquisition_steps_valid_kind,
             check: "kind IN ('santo_decode', 'provider', 'gap')"
           )

    create constraint(:acquisition_steps, :acquisition_steps_valid_status,
             check:
               "status IN ('pending', 'running', 'complete', 'no_record', 'needs_input', 'failed', 'unsupported')"
           )

    create constraint(:acquisition_steps, :acquisition_steps_valid_attempt_count,
             check: "attempt_count >= 0"
           )

    create constraint(:acquisition_steps, :acquisition_steps_valid_shape,
             check: """
             (kind = 'santo_decode'
               AND provider IS NULL
               AND capability = 'vin_identity'
               AND status = 'complete')
             OR
             (kind = 'provider' AND provider IS NOT NULL)
             OR
             (kind = 'gap' AND provider IS NULL AND status = 'unsupported')
             """
           )
  end
end
