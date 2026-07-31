defmodule SantoApi.Repo.Migrations.CreateAdjudications do
  use Ecto.Migration

  def up do
    create table(:adjudications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :claim_a_id, references(:claims, type: :binary_id, on_delete: :restrict), null: false
      add :claim_b_id, references(:claims, type: :binary_id, on_delete: :restrict), null: false

      add :prevailing_claim_id, references(:claims, type: :binary_id, on_delete: :restrict)

      add :decided_by_party_id, references(:parties, type: :binary_id, on_delete: :restrict),
        null: false

      add :evidence_request_id,
          references(:evidence_requests, type: :binary_id, on_delete: :restrict)

      add :outcome, :string, null: false
      add :evidence_artifact_ids, {:array, :binary_id}, null: false, default: []
      add :requested_evidence_classes, {:array, :string}, null: false, default: []
      add :note, :text
      add :content_hash, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:adjudications, [:vehicle_id])
    create index(:adjudications, [:claim_a_id])
    create index(:adjudications, [:claim_b_id])
    create unique_index(:adjudications, [:content_hash])

    create constraint(:adjudications, :adjudications_distinct_claims,
             check: "claim_a_id <> claim_b_id"
           )

    create constraint(:adjudications, :adjudications_valid_outcome,
             check: """
             (outcome = 'supersede'
               AND prevailing_claim_id IN (claim_a_id, claim_b_id)
               AND cardinality(evidence_artifact_ids) > 0
               AND evidence_request_id IS NULL)
             OR
             (outcome = 'coexist-with-note'
               AND prevailing_claim_id IS NULL
               AND cardinality(evidence_artifact_ids) > 0
               AND length(btrim(note)) > 0
               AND evidence_request_id IS NULL)
             OR
             (outcome = 'request-evidence'
               AND prevailing_claim_id IS NULL
               AND cardinality(requested_evidence_classes) > 0
               AND evidence_request_id IS NOT NULL)
             """
           )

    execute """
    CREATE FUNCTION prevent_adjudication_changes()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'adjudications are append-only';
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER adjudications_append_only
    BEFORE UPDATE OR DELETE ON adjudications
    FOR EACH ROW EXECUTE FUNCTION prevent_adjudication_changes()
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS adjudications_append_only ON adjudications"
    execute "DROP FUNCTION IF EXISTS prevent_adjudication_changes()"
    drop table(:adjudications)
  end
end
