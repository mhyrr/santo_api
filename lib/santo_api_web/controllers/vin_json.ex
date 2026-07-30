defmodule SantoApiWeb.VinJSON do
  @moduledoc """
  Renders `Santo.decode/1` results as JSON.

  Santo structs carry atoms, tuples, keyword lists, and nested structs
  that Jason can't encode directly. `sanitize/1` is the single recursive
  rule that makes them JSON-safe: structs and maps become plain maps
  (keys and values sanitized), lists and tuples both become JSON arrays,
  atoms become strings (except nil/true/false), everything else is left
  as-is.
  """

  def show(%{decoded: decoded}) do
    %{status: "ok", decoded: sanitize(decoded)}
  end

  def ambiguous(%{candidates: candidates}) do
    %{status: "ambiguous", candidates: sanitize(candidates)}
  end

  def invalid(%{invalid: invalid}) do
    Map.put(sanitize(invalid), :status, "invalid")
  end

  defp sanitize(nil), do: nil
  defp sanitize(true), do: true
  defp sanitize(false), do: false

  defp sanitize(%_struct{} = struct) do
    struct |> Map.from_struct() |> sanitize()
  end

  defp sanitize(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {sanitize(k), sanitize(v)} end)
  end

  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)

  defp sanitize(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> sanitize()
  end

  defp sanitize(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp sanitize(other), do: other
end
