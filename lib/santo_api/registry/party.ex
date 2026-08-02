defmodule SantoApi.Registry.Party do
  @moduledoc """
  Who is doing the asserting. A party's name is the identity a claim is
  attributed to, and for an owner that name is their public handle.

  The name is permanent. It joins every claim's `content_hash`, so renaming a
  party would orphan its own history's hashes (owner_surface §9.1). Validation
  therefore happens once, on the way in, and there is no update changeset.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Lowercase, starts and ends alphanumeric, hyphens and underscores inside.
  # Narrow on purpose: a handle gets read off a screen and typed into a phone,
  # and it can never be corrected once a claim carries it.
  @handle_format ~r/\A[a-z0-9][a-z0-9_-]*[a-z0-9]\z/

  schema "parties" do
    field :name, :string
    field :kind, Ecto.Enum, values: [:owner, :vendor, :shop, :registry, :vin_santo]
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  An owner party from a chosen handle.

  Case and surrounding space are normalized before validation, because the
  normalized form is the one that becomes permanent — better to settle it here
  than to hash whatever the keyboard produced.
  """
  def handle_changeset(handle) when is_binary(handle) do
    %__MODULE__{kind: :owner}
    |> cast(%{name: normalize_handle(handle)}, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 3, max: 32)
    |> validate_format(:name, @handle_format,
      message: "must be lowercase letters, numbers, hyphens or underscores"
    )
    |> unique_constraint(:name, name: :parties_name_kind_index)
  end

  defp normalize_handle(handle), do: handle |> String.trim() |> String.downcase()
end
