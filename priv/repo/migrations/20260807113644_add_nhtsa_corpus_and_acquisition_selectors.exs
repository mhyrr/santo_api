defmodule SantoApi.Repo.Migrations.AddNhtsaCorpusAndAcquisitionSelectors do
  use Ecto.Migration

  def change do
    alter table(:acquisition_steps) do
      add :depends_on_step_id,
          references(:acquisition_steps, type: :binary_id, on_delete: :restrict)

      add :selectors, :map, null: false, default: %{}
      add :conflicted_selectors, {:array, :string}, null: false, default: []
    end

    create index(:acquisition_steps, [:depends_on_step_id])

    create constraint(:acquisition_steps, :acquisition_steps_no_self_dependency,
             check: "depends_on_step_id IS NULL OR depends_on_step_id <> id"
           )

    create table(:corpus_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :dataset, :string, null: false
      add :source_key, :string, null: false
      add :release_key, :string, null: false
      add :released_on, :date, null: false
      add :source_url, :string, null: false
      add :acquired_at, :utc_datetime_usec, null: false
      add :sha256, :string, null: false
      add :storage_ref, :string, null: false
      add :media_type, :string, null: false
      add :rights_profile, :string, null: false
      add :status, :string, null: false, default: "importing"
      add :coverage, :string
      add :record_count, :integer, null: false, default: 0
      add :malformed_row_count, :integer, null: false, default: 0
      add :diagnostics, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:corpus_releases, [:dataset, :source_key, :release_key])
    create index(:corpus_releases, [:dataset, :source_key, :released_on])
    create index(:corpus_releases, [:dataset, :status])

    create constraint(:corpus_releases, :corpus_releases_valid_status,
             check: "status IN ('importing', 'imported', 'failed')"
           )

    create constraint(:corpus_releases, :corpus_releases_valid_coverage,
             check: "coverage IS NULL OR coverage IN ('complete', 'partial')"
           )

    create constraint(:corpus_releases, :corpus_releases_valid_counts,
             check: "record_count >= 0 AND malformed_row_count >= 0"
           )

    create table(:corpus_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :release_id,
          references(:corpus_releases, type: :binary_id, on_delete: :restrict),
          null: false

      add :source_row, :integer, null: false
      add :record_key, :string, null: false
      add :marque, :string, null: false
      add :model, :string, null: false
      add :model_year, :integer, null: false
      add :payload, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:corpus_records, [:release_id, :record_key])

    create index(:corpus_records, [:release_id, :model_year, :marque, :model],
             name: :corpus_records_selector_index
           )

    create constraint(:corpus_records, :corpus_records_valid_source_row, check: "source_row > 0")

    create constraint(:corpus_records, :corpus_records_valid_model_year,
             check: "model_year BETWEEN 1886 AND 2200"
           )
  end
end
