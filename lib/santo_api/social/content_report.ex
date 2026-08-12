defmodule SantoApi.Social.ContentReport do
  @moduledoc """
  A member's request for operator review of a public car or update.

  The target follows the public surface's actual shape: one vehicle and, for
  an update, its shared `entry_ref`. Resolution retains the deciding operator,
  note, and time rather than deleting the report.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @reasons ~w(abuse doxxing fraud other)
  @reason_values [:abuse, :doxxing, :fraud, :other]

  schema "content_reports" do
    field :target_kind, Ecto.Enum, values: [:vehicle, :entry]
    belongs_to :vehicle, Vehicle
    field :entry_ref, Ecto.UUID
    belongs_to :reporter_user, User
    field :reporter_handle, :string
    field :reason, Ecto.Enum, values: @reason_values
    field :detail, :string
    field :status, Ecto.Enum, values: [:open, :dismissed, :actioned], default: :open
    belongs_to :decided_by_user, User
    field :decided_at, :utc_datetime_usec
    field :decision_note, :string
    timestamps(type: :utc_datetime_usec)
  end

  def reasons, do: @reasons

  def create_changeset(target_kind, vehicle_id, entry_ref, user, attrs)
      when target_kind in [:vehicle, :entry] do
    %__MODULE__{}
    |> cast(attrs, [:reason, :detail])
    |> update_change(:detail, &trimmed/1)
    |> validate_required([:reason])
    |> validate_length(:detail, max: 1_000)
    |> put_change(:target_kind, target_kind)
    |> put_change(:vehicle_id, vehicle_id)
    |> put_change(:entry_ref, entry_ref)
    |> put_change(:reporter_user_id, user.id)
    |> put_change(:reporter_handle, user.handle)
    |> validate_required([:target_kind, :vehicle_id, :reporter_user_id, :reporter_handle])
    |> validate_target()
    |> unique_target_constraint(target_kind)
    |> foreign_key_constraint(:vehicle_id)
    |> foreign_key_constraint(:reporter_user_id)
  end

  defp validate_target(changeset) do
    case {get_field(changeset, :target_kind), get_field(changeset, :entry_ref)} do
      {:vehicle, nil} -> changeset
      {:entry, entry_ref} when not is_nil(entry_ref) -> changeset
      _invalid -> add_error(changeset, :entry_ref, "does not match the report target")
    end
  end

  defp unique_target_constraint(changeset, :vehicle) do
    unique_constraint(changeset, [:vehicle_id, :reporter_user_id],
      name: :content_reports_vehicle_reporter_index,
      message: "has already been reported by this account"
    )
  end

  defp unique_target_constraint(changeset, :entry) do
    unique_constraint(changeset, [:vehicle_id, :entry_ref, :reporter_user_id],
      name: :content_reports_entry_reporter_index,
      message: "has already been reported by this account"
    )
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end
end
