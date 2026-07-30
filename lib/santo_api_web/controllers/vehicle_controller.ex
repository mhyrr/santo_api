defmodule SantoApiWeb.VehicleController do
  use SantoApiWeb, :controller

  alias SantoApi.Registry

  def create(conn, %{"input" => input}) do
    case Registry.ingest(input) do
      {:ok, vehicle} ->
        conn
        |> put_status(:created)
        |> render(:show, payload(vehicle))

      {:error, %Santo.Invalid{} = invalid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(SantoApiWeb.VinJSON)
        |> render(:invalid, invalid: invalid)
    end
  end

  def show(conn, %{"id" => id}) do
    case Registry.fetch_vehicle(id) do
      {:ok, vehicle} ->
        render(conn, :show, payload(vehicle))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "not_found"})
    end
  end

  defp payload(vehicle) do
    [
      vehicle: vehicle,
      claims: Registry.list_claims(vehicle.id),
      evidence_requests: Registry.list_evidence_requests(vehicle.id)
    ]
  end
end
