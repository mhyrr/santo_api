defmodule SantoApi.Events.EventParticipation do
  @moduledoc """
  One member and car's account of a shared event occurrence.

  `entry_ref` points at the ordinary owner update that carries replies and its
  permalink. The ordered details here are event-local prose; they never fold
  into `Vehicle.current_state`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Events.{EventAttachment, EventDetail, EventOccurrence}
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_participations" do
    belongs_to :event, EventOccurrence
    belongs_to :vehicle, Vehicle
    belongs_to :user, User
    field :entry_ref, Ecto.UUID
    field :journal, :string
    field :tags, {:array, :string}, default: []
    embeds_many :details, EventDetail, on_replace: :delete
    field :visibility, Ecto.Enum, values: [:public, :private], default: :public

    has_many :attachments, EventAttachment, foreign_key: :participation_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [:journal, :tags, :visibility])
    |> update_change(:journal, &trim/1)
    |> normalize_tags()
    |> cast_embed(:details, with: &EventDetail.changeset/2)
    |> validate_required([:event_id, :vehicle_id, :user_id, :entry_ref, :journal, :visibility])
    |> validate_length(:journal, max: 12_000)
    |> validate_length(:tags, max: 12)
    |> unique_constraint([:event_id, :vehicle_id])
    |> unique_constraint([:vehicle_id, :entry_ref])
  end

  defp normalize_tags(changeset) do
    update_change(changeset, :tags, fn tags ->
      if is_list(tags) do
        tags
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
      else
        tags
      end
    end)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
