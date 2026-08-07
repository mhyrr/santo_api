defmodule SantoApi.Registry.IdentityKey do
  @moduledoc """
  Canonical string form of a `Santo.Identity` term, used as the
  registry's unique key (evidence contract §1).

  `{:asserted, id}` is the registry's own constructor, not santo's
  (owner_surface §7b): a car originated before it has any identifier,
  keyed on a minted opaque id. `Santo.Identity.key/1` never returns it —
  the only mint is `Registry.originate/1`, and the only exit is
  `Registry.resolve_asserted/2` acquiring a real VIN.
  """

  def serialize({:vin, vin}), do: "vin:" <> vin

  def serialize({:chassis, marque, era, number}),
    do: Enum.join(["chassis", marque, era, number], ":")

  def serialize({:disputed, candidates, _evidence}),
    do: "disputed:" <> Enum.map_join(candidates, "|", &serialize/1)

  def serialize({:asserted, id}), do: "asserted:" <> id

  def kind({:vin, _}), do: :vin
  def kind({:chassis, _, _, _}), do: :chassis
  def kind({:disputed, _, _}), do: :disputed
  def kind({:asserted, _}), do: :asserted

  def candidates({:disputed, candidates, _}), do: Enum.map(candidates, &serialize/1)
  def candidates(_), do: []
end
