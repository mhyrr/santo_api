defmodule SantoApi.Nhtsa.Corpus.Record do
  @moduledoc """
  A source row normalized only far enough for year/marque/model lookup.

  Source-specific reference facts remain in `payload`; they are never vehicle
  claims merely because a model-population selector matched.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Nhtsa.Corpus.Release

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "corpus_records" do
    belongs_to :release, Release

    field :source_row, :integer
    field :record_key, :string
    field :marque, :string
    field :model, :string
    field :model_year, :integer
    field :payload, :map
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(%Release{} = release, attrs) do
    %__MODULE__{release_id: release.id}
    |> cast(attrs, [:source_row, :record_key, :marque, :model, :model_year, :payload])
    |> validate_required([:source_row, :record_key, :marque, :model, :model_year, :payload])
    |> validate_number(:source_row, greater_than: 0)
    |> validate_number(:model_year, greater_than_or_equal_to: 1886, less_than_or_equal_to: 2200)
    |> foreign_key_constraint(:release_id)
    |> unique_constraint([:release_id, :record_key])
  end
end
