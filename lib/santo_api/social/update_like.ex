defmodule SantoApi.Social.UpdateLike do
  @moduledoc """
  One member appreciating one public update.

  A like is presentation data. It never enters the claim ledger and never
  contributes to record strength, verification, or ranking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "update_likes" do
    belongs_to :vehicle, Vehicle
    field :entry_ref, Ecto.UUID
    belongs_to :user, User
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(vehicle_id, entry_ref, user_id) do
    %__MODULE__{}
    |> change(vehicle_id: vehicle_id, entry_ref: entry_ref, user_id: user_id)
    |> validate_required([:vehicle_id, :entry_ref, :user_id])
    |> unique_constraint([:vehicle_id, :entry_ref, :user_id])
    |> foreign_key_constraint(:vehicle_id)
    |> foreign_key_constraint(:user_id)
  end
end
