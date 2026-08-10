defmodule SantoApi.Events.EventOccurrence do
  @moduledoc """
  The universal shared coordinate for something that happened.

  It carries only title, time, place, description, tags, and source posture.
  Discipline-specific concepts belong in participant prose and details unless
  a future typed adapter earns a separate model.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Events.EventParticipation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @public_id_bytes 6

  schema "event_occurrences" do
    field :public_id, :string
    belongs_to :creator_user, User
    field :title, :string
    field :starts_on, :date
    field :ends_on, :date
    field :starts_at, :time
    field :ends_at, :time
    field :timezone, :string
    field :place_text, :string
    field :description, :string
    field :tags, {:array, :string}, default: []

    field :source_status, Ecto.Enum,
      values: [:community, :organizer, :imported],
      default: :community

    field :participant_count, :integer, virtual: true, default: 0
    field :media_count, :integer, virtual: true, default: 0

    has_many :participations, EventParticipation, foreign_key: :event_id
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :title,
      :starts_on,
      :ends_on,
      :starts_at,
      :ends_at,
      :timezone,
      :place_text,
      :description,
      :tags
    ])
    |> normalize_text([:title, :place_text, :description, :timezone])
    |> normalize_tags()
    |> validate_required([:title, :starts_on, :place_text])
    |> validate_length(:title, max: 160)
    |> validate_length(:place_text, max: 200)
    |> validate_length(:description, max: 4_000)
    |> validate_length(:timezone, max: 80)
    |> validate_length(:tags, max: 12)
    |> validate_date_order()
    |> validate_time_order()
    |> unique_constraint(:public_id)
    |> check_constraint(:ends_on, name: :event_occurrences_date_order)
  end

  def mint_public_id do
    @public_id_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(padding: false)
    |> String.downcase()
  end

  defp normalize_text(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, acc ->
      update_change(acc, field, fn value ->
        case trim(value) do
          "" -> nil
          text -> text
        end
      end)
    end)
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

  defp validate_date_order(changeset) do
    case {get_field(changeset, :starts_on), get_field(changeset, :ends_on)} do
      {%Date{} = starts_on, %Date{} = ends_on} ->
        if Date.before?(ends_on, starts_on),
          do: add_error(changeset, :ends_on, "cannot be before the start date"),
          else: changeset

      _other ->
        changeset
    end
  end

  defp validate_time_order(changeset) do
    same_day? = get_field(changeset, :ends_on) in [nil, get_field(changeset, :starts_on)]

    case {same_day?, get_field(changeset, :starts_at), get_field(changeset, :ends_at)} do
      {true, %Time{} = starts_at, %Time{} = ends_at} ->
        if Time.before?(ends_at, starts_at),
          do: add_error(changeset, :ends_at, "cannot be before the start time"),
          else: changeset

      _other ->
        changeset
    end
  end
end
