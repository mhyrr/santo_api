defmodule SantoApi.Social.UpdateComment do
  @moduledoc """
  A reply to one logbook update.

  Replies are conversation about the record, not evidence inside it. The
  public handle is snapshotted so attribution survives an account lifecycle;
  the optional user id remains the authorization seam for withdrawal.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @body_max_length 2_000

  schema "update_comments" do
    belongs_to :vehicle, Vehicle
    field :entry_ref, Ecto.UUID
    belongs_to :author_user, User
    field :author_handle, :string
    field :body, :string
    field :status, Ecto.Enum, values: [:visible, :withdrawn, :hidden], default: :visible
    field :withdrawn_at, :utc_datetime_usec
    field :hidden_at, :utc_datetime_usec
    belongs_to :hidden_by_user, User
    field :moderation_note, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(vehicle_id, entry_ref, user, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: @body_max_length)
    |> put_change(:vehicle_id, vehicle_id)
    |> put_change(:entry_ref, entry_ref)
    |> put_change(:author_user_id, user.id)
    |> put_change(:author_handle, user.handle)
    |> validate_required([:vehicle_id, :entry_ref, :author_user_id, :author_handle])
    |> foreign_key_constraint(:vehicle_id)
    |> foreign_key_constraint(:author_user_id)
  end
end
