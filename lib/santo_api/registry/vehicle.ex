defmodule SantoApi.Registry.Vehicle do
  @moduledoc """
  A registry row names a physical chassis, keyed by the canonical form
  of `Santo.Identity.key/1`. The surrogate id is the stable reference —
  identity is an attribute, correctable by adjudication (contract §1).
  A `:disputed` row carries its candidate identities as data.

  Two derived maps hang off the row, both folded from the ledger and both
  replayable: `facts` is what the factory built (contract §8), `current_state`
  is what the car is now (owner_surface §2b). They are computed independently
  — divergence between them is the build story, and it is calculated at render
  time, never stored.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicles" do
    field :identity_kind, Ecto.Enum, values: [:vin, :chassis, :disputed]
    field :identity_key, :string
    field :candidates, {:array, :string}, default: []
    field :input, :string
    field :decode_snapshot, :map
    field :santo_version, :string
    field :facts, :map, default: %{}
    field :current_state, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
