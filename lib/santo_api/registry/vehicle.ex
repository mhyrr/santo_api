defmodule SantoApi.Registry.Vehicle do
  @moduledoc """
  A registry row names a physical chassis, keyed by the canonical form
  of `Santo.Identity.key/1`. The surrogate id is the stable reference —
  identity is an attribute, correctable by adjudication (contract §1).
  A `:disputed` row carries its candidate identities as data.
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
    timestamps(type: :utc_datetime_usec)
  end
end
