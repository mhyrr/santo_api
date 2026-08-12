defmodule SantoApiWeb.VehicleController do
  use SantoApiWeb, :controller

  alias SantoApi.{Owners, Registry}

  def create(conn, %{"input" => input}) do
    case Registry.ingest(input) do
      {:ok, vehicle} when vehicle.visibility == :public ->
        conn
        |> put_status(:created)
        |> render(:show, payload(vehicle))

      {:ok, _hidden} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "not_found"})

      {:error, %Santo.Invalid{} = invalid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(SantoApiWeb.VinJSON)
        |> render(:invalid, invalid: invalid)
    end
  end

  def show(conn, %{"id" => id}) do
    case Registry.fetch_vehicle(id) do
      {:ok, vehicle} when vehicle.visibility != :public ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "not_found"})

      {:ok, vehicle} ->
        render(conn, :show, payload(vehicle))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{status: "not_found"})
    end
  end

  def vpic(conn, %{"id" => id}) do
    with {:ok, vehicle} <- Registry.fetch_vehicle(id),
         true <- Owners.published?(vehicle),
         {:ok, artifact} <- Registry.ingest_vpic(vehicle),
         {:ok, vehicle} <- Registry.fetch_vehicle(id) do
      conn
      |> put_status(:created)
      |> render(:evidence, Keyword.put(payload(vehicle), :artifact, artifact))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{status: "not_found"})

      false ->
        conn |> put_status(:not_found) |> json(%{status: "not_found"})

      {:error, :unsupported_identity} ->
        conn |> put_status(:unprocessable_entity) |> json(%{status: "unsupported_identity"})

      {:error, _reason} ->
        conn |> put_status(:bad_gateway) |> json(%{status: "vpic_unavailable"})
    end
  end

  defp payload(vehicle) do
    [
      vehicle: vehicle,
      claims: Registry.list_public_claims(vehicle.id),
      evidence_requests: Registry.list_evidence_requests(vehicle.id),
      comparison: Registry.public_claim_comparison(vehicle.id)
    ]
  end
end
