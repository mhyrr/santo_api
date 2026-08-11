defmodule SantoApi.Events.EventDetail do
  @moduledoc """
  One owner-named label/value detail on an event participation.

  Both sides stay text. A detail may say `Best run / 44.182` or
  `Photographer / @handle`, but this schema deliberately gives neither value
  arithmetic meaning. A future typed adapter may interpret a copy; the source
  remains the owner's words.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :label, :string
    field :value, :string
  end

  def changeset(detail, attrs) do
    detail
    |> cast(attrs, [:label, :value])
    |> update_change(:label, &trim/1)
    |> update_change(:value, &trim/1)
    |> validate_required([:label, :value])
    |> validate_length(:label, max: 80)
    |> validate_length(:value, max: 240)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
