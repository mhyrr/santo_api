defmodule SantoApi.Nhtsa.Corpus.Release do
  @moduledoc """
  One preserved official NHTSA dataset release.

  Releases are immutable by `{dataset, source_key, release_key}`. The raw archive
  remains in artifact storage while normalized records provide the lookup index.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Nhtsa.Corpus.Record

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "corpus_releases" do
    has_many :records, Record

    field :dataset, :string
    field :source_key, :string
    field :release_key, :string
    field :released_on, :date
    field :source_url, :string
    field :acquired_at, :utc_datetime_usec
    field :sha256, :string
    field :storage_ref, :string
    field :media_type, :string
    field :rights_profile, :string
    field :status, Ecto.Enum, values: [:importing, :imported, :failed], default: :importing
    field :coverage, Ecto.Enum, values: [:complete, :partial]
    field :record_count, :integer, default: 0
    field :malformed_row_count, :integer, default: 0
    field :diagnostics, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :dataset,
      :source_key,
      :release_key,
      :released_on,
      :source_url,
      :acquired_at,
      :sha256,
      :storage_ref,
      :media_type,
      :rights_profile,
      :status,
      :coverage,
      :record_count,
      :malformed_row_count,
      :diagnostics
    ])
    |> validate_required([
      :dataset,
      :source_key,
      :release_key,
      :released_on,
      :source_url,
      :acquired_at,
      :sha256,
      :storage_ref,
      :media_type,
      :rights_profile,
      :status
    ])
    |> validate_format(:sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:record_count, greater_than_or_equal_to: 0)
    |> validate_number(:malformed_row_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:dataset, :source_key, :release_key])
  end
end
