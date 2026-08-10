defmodule SantoApi.Owners.VehicleStory do
  @moduledoc """
  Mutable owner-authored opening prose for a car page.

  A story is curation, not a claim. It changes in place as the relationship
  with the car changes and never enters the registry ledger or current-state
  fold.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicle_stories" do
    belongs_to :vehicle, Vehicle
    belongs_to :author_user, User
    field :tagline, :string
    field :body, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(story, attrs) do
    story
    |> cast(attrs, [:tagline, :body])
    |> update_change(:tagline, &trim/1)
    |> update_change(:body, &blank_to_nil/1)
    |> validate_required([:vehicle_id, :author_user_id, :tagline])
    |> validate_length(:tagline, max: 180)
    |> validate_length(:body, max: 5_000)
    |> unique_constraint(:vehicle_id)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp blank_to_nil(value) do
    case trim(value) do
      "" -> nil
      value -> value
    end
  end
end
