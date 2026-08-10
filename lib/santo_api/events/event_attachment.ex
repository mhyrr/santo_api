defmodule SantoApi.Events.EventAttachment do
  @moduledoc """
  An ordered, owner-labeled attachment on one participation.

  Uploaded bytes point at the immutable artifact store. External media and
  source links retain their URL. Exactly one target is present.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Events.EventParticipation
  alias SantoApi.Registry.Artifact

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_attachments" do
    belongs_to :participation, EventParticipation
    belongs_to :artifact, Artifact
    field :url, :string
    field :label, :string
    field :kind, Ecto.Enum, values: [:photo, :video, :link, :file]
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:url, :label, :kind, :position])
    |> update_change(:label, &trim/1)
    |> update_change(:url, &trim/1)
    |> validate_required([:participation_id, :label, :kind, :position])
    |> validate_length(:label, max: 120)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_target()
    |> validate_url()
    |> check_constraint(:url, name: :event_attachments_one_target)
  end

  defp validate_target(changeset) do
    case {get_field(changeset, :artifact_id), get_field(changeset, :url)} do
      {artifact_id, nil} when not is_nil(artifact_id) -> changeset
      {nil, url} when is_binary(url) and url != "" -> changeset
      _other -> add_error(changeset, :url, "must supply one file or link")
    end
  end

  defp validate_url(changeset) do
    case get_field(changeset, :url) do
      nil ->
        changeset

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and is_binary(host) and host != "" ->
            changeset

          _invalid ->
            add_error(changeset, :url, "must be a valid http or https URL")
        end
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
