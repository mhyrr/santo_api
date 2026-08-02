defmodule SantoApiWeb.VehiclePageController do
  @moduledoc """
  Resolves a VIN to the canonical car page.

  VINs are the identifier everyone has — printed on the listing, visible
  through the windscreen — so they make a good way in. They make a bad URL:
  identity is an attribute of the row and correctable (contract §1), and a
  shared link has to survive the correction. So this redirects and the page
  itself hangs on the public handle.
  """
  use SantoApiWeb, :controller

  alias SantoApi.Registry

  def resolve(conn, %{"vin" => vin}) do
    case Registry.resolve_vin(vin) do
      {:ok, vehicle} -> redirect(conn, to: ~p"/v/#{vehicle.public_id}")
      {:error, :not_found} -> raise SantoApiWeb.VehicleNotFound
    end
  end
end
