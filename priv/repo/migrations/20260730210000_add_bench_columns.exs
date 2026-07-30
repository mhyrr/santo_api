defmodule SantoApi.Repo.Migrations.AddBenchColumns do
  use Ecto.Migration

  def change do
    alter table(:artifacts) do
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict)
    end

    create index(:artifacts, [:vehicle_id])

    alter table(:evidence_requests) do
      add :satisfied_by_claim_id, references(:claims, type: :binary_id, on_delete: :restrict)

      add :satisfied_by_artifact_id,
          references(:artifacts, type: :binary_id, on_delete: :restrict)
    end
  end
end
