defmodule SantoApi.Registry.Artifact do
  @moduledoc """
  An immutable acquired thing (contract §2): document, photo, receipt,
  API snapshot, listing. Artifacts evidence claims; they assert nothing
  by themselves. A re-fetch is a new artifact. For api_snapshot the
  content lives in `payload`; file-backed kinds will use `storage_ref`.
  """

  use Ecto.Schema

  alias SantoApi.Registry.Party

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "artifacts" do
    belongs_to :source_party, Party
    field :kind, Ecto.Enum, values: [:document, :photo, :receipt, :api_snapshot, :listing]
    field :sha256, :string
    field :payload, :map
    field :storage_ref, :string
    field :mime, :string
    field :source_url, :string
    field :acquired_at, :utc_datetime_usec
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
