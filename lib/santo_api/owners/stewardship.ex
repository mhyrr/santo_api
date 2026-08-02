defmodule SantoApi.Owners.Stewardship do
  @moduledoc """
  One person's authorization to maintain one car's log (owner_surface §4).

  Not a claim, and deliberately not ownership: possession proves access to the
  car, not title. Writing `ownership` into the ledger on this basis would assert
  more than the evidence supports, so the public page says "maintained by".

  Append-only in spirit, like the ledger it guards: revocation is a status flip
  with a reason, never a delete, because the entries a revoked steward logged are
  still in the record and still attributed to them.
  """

  use Ecto.Schema

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.{Artifact, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stewardships" do
    belongs_to :user, User
    belongs_to :vehicle, Vehicle
    belongs_to :proof_artifact, Artifact
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active
    field :reason, :string
    belongs_to :decided_by_user, User
    field :decided_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
