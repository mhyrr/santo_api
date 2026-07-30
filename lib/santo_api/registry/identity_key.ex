defmodule SantoApi.Registry.IdentityKey do
  @moduledoc """
  Canonical string form of a `Santo.Identity` term, used as the
  registry's unique key (evidence contract §1).
  """

  def serialize({:vin, vin}), do: "vin:" <> vin

  def serialize({:chassis, marque, era, number}),
    do: Enum.join(["chassis", marque, era, number], ":")

  def serialize({:disputed, candidates, _evidence}),
    do: "disputed:" <> Enum.map_join(candidates, "|", &serialize/1)

  def kind({:vin, _}), do: :vin
  def kind({:chassis, _, _, _}), do: :chassis
  def kind({:disputed, _, _}), do: :disputed

  def candidates({:disputed, candidates, _}), do: Enum.map(candidates, &serialize/1)
  def candidates(_), do: []
end
