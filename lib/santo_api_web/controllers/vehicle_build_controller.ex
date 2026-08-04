defmodule SantoApiWeb.VehicleBuildController do
  @moduledoc """
  The explicit write boundary for an anonymous public VIN build.

  The form that calls this action lives in the public LiveView session, while
  the POST stays a controller action so every submission passes through the
  request rate limiter.
  """

  use SantoApiWeb, :controller

  alias SantoApi.AcquisitionRuns

  def create(conn, %{"vin" => vin}) do
    case AcquisitionRuns.start(conn.assigns.current_scope, vin) do
      {:ok, _disposition, vehicle, _run} ->
        redirect(conn, to: ~p"/v/#{vehicle.public_id}")

      {:error, %Santo.Invalid{}} ->
        invalid_vin(conn, "That VIN is not valid.")

      {:error, :vin_required} ->
        invalid_vin(conn, "Enter a standard 17-character VIN.")
    end
  end

  def create(conn, _params), do: invalid_vin(conn, "Enter a standard 17-character VIN.")

  defp invalid_vin(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/")
  end
end
