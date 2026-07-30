defmodule SantoApi.Terms do
  @moduledoc """
  Makes santo's term-shaped data JSON-safe with one uniform rule.

  Santo structs carry atoms, tuples, keyword lists, and nested structs.
  `sanitize/1` applies a single recursive rule: structs and maps become
  plain maps (keys and values sanitized), lists and tuples both become
  arrays, atoms become strings (except nil/true/false), everything else
  is left as-is. Used both by the JSON views and by the registry when
  snapshotting decodes.
  """

  def sanitize(nil), do: nil
  def sanitize(true), do: true
  def sanitize(false), do: false

  def sanitize(%_struct{} = struct) do
    struct |> Map.from_struct() |> sanitize()
  end

  def sanitize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {sanitize(k), sanitize(v)} end)
  end

  def sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)

  def sanitize(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> sanitize()
  end

  def sanitize(atom) when is_atom(atom), do: Atom.to_string(atom)

  def sanitize(other), do: other
end
