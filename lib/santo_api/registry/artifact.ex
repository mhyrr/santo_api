defmodule SantoApi.Registry.Artifact do
  @moduledoc """
  An immutable acquired thing (contract §2): document, photo, receipt,
  API snapshot, listing, or source reference. Artifacts evidence claims;
  they assert nothing by themselves. A re-fetch is a new artifact. For
  api_snapshot the content lives in `payload`; file-backed kinds use
  `storage_ref`; references retain only a pointer and rights metadata.
  """

  use Ecto.Schema

  alias SantoApi.Registry.{Party, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "artifacts" do
    belongs_to(:source_party, Party)
    belongs_to(:vehicle, Vehicle)

    field(
      :kind,
      Ecto.Enum,
      values: [:document, :photo, :receipt, :api_snapshot, :listing, :reference]
    )

    field(:acquisition_id, Ecto.UUID)

    # Shared with the claims of the same composed entry, so a three-photo
    # entry hangs together where a claim's single `artifact_id` cannot.
    field(:entry_ref, Ecto.UUID)
    field(:sha256, :string)
    field(:payload, :map)
    field(:storage_ref, :string)
    field(:mime, :string)
    field(:source_url, :string)
    field(:acquired_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    # Presentation state (owner_surface §6). The artifact itself never changes;
    # this only governs who is shown it.
    field(:visibility, Ecto.Enum, values: [:public, :private], default: :public)
    timestamps(type: :utc_datetime_usec)
  end
end
