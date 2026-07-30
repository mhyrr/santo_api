defmodule SantoApi.Registry.Claim do
  @moduledoc """
  The atom of the registry (contract §3): one typed assertion about one
  vehicle. Append-only — corrections are new claims plus an adjudication,
  never edits. `content_hash` is the attestation seam: a deterministic
  digest of the claim's substance, so admitted claim sets can be hashed.
  """

  use Ecto.Schema

  alias SantoApi.Registry.{JsonValue, Party, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "claims" do
    belongs_to :vehicle, Vehicle
    belongs_to :asserted_by_party, Party
    field :predicate, :string
    field :value, JsonValue
    field :scope_kind, Ecto.Enum, values: [:factory, :observed, :event]
    field :scope_date, :date

    field :state, Ecto.Enum,
      values: [:proposed, :admitted, :rejected, :superseded, :retracted],
      default: :proposed

    field :method, Ecto.Enum, values: [:santo, :structured_api, :llm_extract, :human]
    field :method_meta, :map, default: %{}
    field :content_hash, :string
    timestamps(type: :utc_datetime_usec)
  end

  def hash(identity_key, predicate, value, scope_kind, scope_date, method) do
    payload = Jason.encode!([identity_key, predicate, value, scope_kind, scope_date, method])
    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end
end
