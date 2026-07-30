defmodule SantoApi.Registry.Claim do
  @moduledoc """
  The atom of the registry (contract §3): one typed assertion about one
  vehicle. Append-only — corrections are new claims plus an adjudication,
  never edits. `content_hash` is the attestation seam: a deterministic
  digest of the claim's substance, so admitted claim sets can be hashed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Registry.{Artifact, JsonValue, Party, Vehicle, Vocabulary}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "claims" do
    belongs_to :vehicle, Vehicle
    belongs_to :asserted_by_party, Party
    belongs_to :artifact, Artifact
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

  @doc """
  Changeset for a human-proposed claim (the bench path). Vocabulary
  validation sets the scope kind; basis fields are stamped from the
  vehicle and asserting party, never cast.
  """
  def propose_changeset(%Vehicle{} = vehicle, %Party{} = party, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:predicate, :value, :scope_date, :artifact_id])
    |> validate_required([:predicate, :value])
    |> validate_vocabulary()
    |> put_basis(vehicle, party)
    |> unique_constraint(:content_hash, name: :claims_vehicle_id_content_hash_index)
    |> foreign_key_constraint(:artifact_id)
  end

  defp validate_vocabulary(changeset) do
    predicate = get_field(changeset, :predicate)
    value = get_field(changeset, :value)

    if changeset.valid? do
      case Vocabulary.validate(predicate, value) do
        :ok -> put_change(changeset, :scope_kind, Vocabulary.scope_kind(predicate))
        {:error, reason} -> add_error(changeset, :predicate, inspect(reason))
      end
    else
      changeset
    end
  end

  defp put_basis(%{valid?: false} = changeset, _vehicle, _party), do: changeset

  defp put_basis(changeset, vehicle, party) do
    predicate = get_field(changeset, :predicate)
    value = get_field(changeset, :value)
    scope_kind = get_field(changeset, :scope_kind)
    scope_date = get_field(changeset, :scope_date)

    changeset
    |> put_change(:vehicle_id, vehicle.id)
    |> put_change(:asserted_by_party_id, party.id)
    |> put_change(:method, :human)
    |> put_change(:state, :proposed)
    |> put_change(
      :content_hash,
      hash(vehicle.identity_key, predicate, value, scope_kind, scope_date, :human, party.name)
    )
  end

  def hash(identity_key, predicate, value, scope_kind, scope_date, method, party_name) do
    payload =
      Jason.encode!([identity_key, predicate, value, scope_kind, scope_date, method, party_name])

    :crypto.hash(:sha256, payload) |> Base.encode16(case: :lower)
  end
end
