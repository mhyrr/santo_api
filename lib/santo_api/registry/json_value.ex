defmodule SantoApi.Registry.JsonValue do
  @moduledoc """
  A jsonb column holding any JSON value, not only objects — claim values
  are scalars, objects, or arrays depending on predicate (contract §3).
  """

  use Ecto.Type

  def type, do: :map

  def cast(value), do: {:ok, value}
  def dump(value), do: {:ok, value}
  def load(value), do: {:ok, value}
end
