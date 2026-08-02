defmodule SantoApiWeb.VehicleNotFound do
  @moduledoc """
  Raised when a public handle or VIN names no car we hold. Renders 404 rather
  than 500 — an unknown car is a normal answer on a public lookup surface.
  """
  defexception message: "no car with that identifier", plug_status: 404
end
