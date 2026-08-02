defmodule SantoApi.Repo.Migrations.DistinguishProviderAcquisitions do
  use Ecto.Migration

  def up do
    alter table(:artifacts) do
      add(:acquisition_id, :uuid)
    end

    execute("UPDATE artifacts SET acquisition_id = gen_random_uuid() WHERE kind = 'api_snapshot'")

    drop(unique_index(:artifacts, [:sha256]))

    create(
      unique_index(:artifacts, [:sha256],
        where: "kind <> 'api_snapshot'",
        name: :artifacts_non_snapshot_sha256_index
      )
    )

    create(unique_index(:artifacts, [:acquisition_id], where: "acquisition_id IS NOT NULL"))

    create(
      constraint(:artifacts, :api_snapshot_acquisition_id_required,
        check: "kind <> 'api_snapshot' OR acquisition_id IS NOT NULL"
      )
    )
  end

  def down do
    raise "provider acquisition events cannot be collapsed back into content-deduplicated artifacts"
  end
end
