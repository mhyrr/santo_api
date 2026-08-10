defmodule SantoApi.Owners.VehiclePhoto do
  @moduledoc """
  A mutable placement of an immutable owner-supplied photo on a car page.

  The artifact owns the bytes. This row owns presentation: entry membership,
  alt text, gallery order, hero choice, and visibility. Keeping those choices
  off the content-deduplicated artifact prevents one use of the same bytes from
  changing another entry's privacy or ordering.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.{Artifact, Vehicle}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicle_photos" do
    belongs_to :vehicle, Vehicle
    belongs_to :artifact, Artifact
    belongs_to :author_user, User

    field :entry_ref, Ecto.UUID
    field :entry_date, :date
    field :alt_text, :string
    field :position, :integer, default: 0
    field :hero, :boolean, default: false
    field :visibility, Ecto.Enum, values: [:public, :private], default: :public

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:entry_ref, :entry_date, :alt_text, :position, :hero, :visibility])
    |> update_change(:alt_text, &blank_to_nil/1)
    |> validate_required([
      :vehicle_id,
      :artifact_id,
      :author_user_id,
      :entry_ref,
      :entry_date,
      :position,
      :visibility
    ])
    |> validate_length(:alt_text, max: 240)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> unique_constraint([:vehicle_id, :artifact_id, :entry_ref])
    |> unique_constraint(:vehicle_id, name: :vehicle_photos_one_hero_per_vehicle)
    |> check_constraint(:position, name: :vehicle_photos_position_nonnegative)
    |> check_constraint(:visibility, name: :vehicle_photos_visibility)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp blank_to_nil(value), do: value
end
