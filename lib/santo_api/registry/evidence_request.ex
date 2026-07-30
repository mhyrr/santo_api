defmodule SantoApi.Registry.EvidenceRequest do
  @moduledoc """
  An addressable gap (contract §6): what evidence class would settle a
  question about a vehicle. Generalizes santo's
  `{:evidence_required, subject, classes}` notes into stored state.
  """

  use Ecto.Schema

  alias SantoApi.Registry.{Artifact, Claim, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "evidence_requests" do
    belongs_to :vehicle, Vehicle
    belongs_to :satisfied_by_claim, Claim
    belongs_to :satisfied_by_artifact, Artifact
    field :subject, :string
    field :evidence_classes, {:array, :string}, default: []
    field :status, Ecto.Enum, values: [:open, :satisfied, :abandoned], default: :open
    timestamps(type: :utc_datetime_usec)
  end
end
