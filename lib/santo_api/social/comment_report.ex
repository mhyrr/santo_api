defmodule SantoApi.Social.CommentReport do
  @moduledoc """
  A member's request for an operator to review a reply.

  The reporter's handle is snapshotted for the moderation trail. Resolution is
  a status transition; reports are not deleted after an operator decides them.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SantoApi.Accounts.User
  alias SantoApi.Social.UpdateComment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @reasons ~w(spam harassment privacy other)
  @reason_values [:spam, :harassment, :privacy, :other]

  schema "comment_reports" do
    belongs_to :comment, UpdateComment
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

  def create_changeset(comment_id, user, attrs) do
    %__MODULE__{}
    |> cast(attrs, [:reason, :detail])
    |> update_change(:detail, &trimmed/1)
    |> validate_required([:reason])
    |> validate_length(:detail, max: 1_000)
    |> put_change(:comment_id, comment_id)
    |> put_change(:reporter_user_id, user.id)
    |> put_change(:reporter_handle, user.handle)
    |> validate_required([:comment_id, :reporter_user_id, :reporter_handle])
    |> unique_constraint([:comment_id, :reporter_user_id])
    |> foreign_key_constraint(:comment_id)
    |> foreign_key_constraint(:reporter_user_id)
  end

  defp trimmed(nil), do: nil

  defp trimmed(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end
end
