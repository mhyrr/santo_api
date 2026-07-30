defmodule SantoApi.Repo.Migrations.AddArtifactsAndClaimEvidence do
  use Ecto.Migration

  def change do
    create table(:artifacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_party_id, references(:parties, type: :binary_id, on_delete: :restrict)
      add :kind, :string, null: false
      add :sha256, :string, null: false
      add :payload, :map
      add :storage_ref, :string
      add :mime, :string
      add :source_url, :string
      add :acquired_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:artifacts, [:sha256])

    alter table(:claims) do
      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)
    end

    create index(:claims, [:artifact_id])
  end
end
