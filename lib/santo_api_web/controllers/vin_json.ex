defmodule SantoApiWeb.VinJSON do
  @moduledoc """
  Renders `Santo.decode/1` results as JSON via `SantoApi.Terms.sanitize/1`.
  """

  alias SantoApi.Terms

  def show(%{decoded: decoded}) do
    %{status: "ok", decoded: Terms.sanitize(decoded)}
  end

  def ambiguous(%{candidates: candidates}) do
    %{status: "ambiguous", candidates: Terms.sanitize(candidates)}
  end

  def invalid(%{invalid: invalid}) do
    Map.put(Terms.sanitize(invalid), :status, "invalid")
  end
end
