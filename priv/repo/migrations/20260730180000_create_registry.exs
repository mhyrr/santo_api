defmodule SantoApi.Repo.Migrations.CreateRegistry do
  use Ecto.Migration

  def change do
    create table(:parties, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :kind, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:parties, [:name, :kind])

    create table(:vehicles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identity_kind, :string, null: false
      add :identity_key, :string, null: false
      add :candidates, {:array, :string}, null: false, default: []
      add :input, :string, null: false
      add :decode_snapshot, :map
      add :santo_version, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:vehicles, [:identity_key])

    create table(:claims, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :asserted_by_party_id, references(:parties, type: :binary_id, on_delete: :restrict),
        null: false

      add :predicate, :string, null: false
      add :value, :map, null: false
      add :scope_kind, :string, null: false
      add :scope_date, :date
      add :state, :string, null: false, default: "proposed"
      add :method, :string, null: false
      add :method_meta, :map, null: false, default: %{}
      add :content_hash, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:claims, [:vehicle_id])
    create unique_index(:claims, [:vehicle_id, :content_hash])

    create table(:evidence_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :subject, :string, null: false
      add :evidence_classes, {:array, :string}, null: false, default: []
      add :status, :string, null: false, default: "open"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:evidence_requests, [:vehicle_id, :subject],
             where: "status = 'open'",
             name: :evidence_requests_open_subject_index
           )
  end
end
