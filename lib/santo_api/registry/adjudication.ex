defmodule SantoApi.Registry.Adjudication do
  @moduledoc """
  An immutable resolution record for two incompatible claims (contract §5).

  The claims remain in the ledger. A supersede outcome changes which claim is
  live; this row records who made that call and which artifacts supported it.
  The database rejects updates and deletes so the casebook can only grow.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Registry.{Claim, EvidenceRequest, Party, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "adjudications" do
    belongs_to :vehicle, Vehicle
    belongs_to :claim_a, Claim
    belongs_to :claim_b, Claim
    belongs_to :prevailing_claim, Claim
    belongs_to :decided_by_party, Party
    belongs_to :evidence_request, EvidenceRequest

    field :outcome, Ecto.Enum,
      values: [
        supersede: "supersede",
        coexist_with_note: "coexist-with-note",
        request_evidence: "request-evidence"
      ]

    field :evidence_artifact_ids, {:array, Ecto.UUID}, default: []
    field :requested_evidence_classes, {:array, :string}, default: []
    field :note, :string
    field :content_hash, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(%Party{} = decider, %Claim{} = claim_a, %Claim{} = claim_b, attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :outcome,
      :prevailing_claim_id,
      :evidence_artifact_ids,
      :requested_evidence_classes,
      :note
    ])
    |> validate_required([:outcome])
    |> put_change(:vehicle_id, claim_a.vehicle_id)
    |> put_change(:claim_a_id, claim_a.id)
    |> put_change(:claim_b_id, claim_b.id)
    |> put_change(:decided_by_party_id, decider.id)
    |> validate_outcome()
    |> put_content_hash()
    |> unique_constraint(:content_hash)
    |> check_constraint(:claim_b_id, name: :adjudications_distinct_claims)
    |> check_constraint(:outcome, name: :adjudications_valid_outcome)
  end

  def with_evidence_request(changeset, %EvidenceRequest{} = request) do
    put_change(changeset, :evidence_request_id, request.id)
  end

  defp validate_outcome(changeset) do
    case get_field(changeset, :outcome) do
      :supersede ->
        changeset
        |> validate_required([:prevailing_claim_id])
        |> require_evidence_artifacts()

      :coexist_with_note ->
        changeset
        |> validate_required([:note])
        |> validate_length(:note, min: 1)
        |> require_evidence_artifacts()

      :request_evidence ->
        validate_length(changeset, :requested_evidence_classes, min: 1)

      _ ->
        changeset
    end
  end

  defp require_evidence_artifacts(changeset) do
    validate_length(changeset, :evidence_artifact_ids, min: 1)
  end

  defp put_content_hash(%{valid?: false} = changeset), do: changeset

  defp put_content_hash(changeset) do
    payload = [
      get_field(changeset, :vehicle_id),
      Enum.sort([get_field(changeset, :claim_a_id), get_field(changeset, :claim_b_id)]),
      get_field(changeset, :decided_by_party_id),
      get_field(changeset, :outcome),
      get_field(changeset, :prevailing_claim_id),
      get_field(changeset, :evidence_artifact_ids) |> Enum.sort(),
      get_field(changeset, :requested_evidence_classes) |> Enum.sort(),
      get_field(changeset, :note)
    ]

    hash = payload |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1))
    put_change(changeset, :content_hash, Base.encode16(hash, case: :lower))
  end
end
