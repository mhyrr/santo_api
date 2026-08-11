defmodule SantoApiWeb.VehicleExportController do
  @moduledoc "Serves a steward's private, portable vehicle record archive."

  use SantoApiWeb, :controller

  alias SantoApi.{Owners, Registry}

  def show(conn, %{"public_id" => public_id}) do
    with {:ok, vehicle} <- Registry.fetch_by_public_id(public_id),
         {:ok, archive} <- Owners.export_record(conn.assigns.current_scope, vehicle) do
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_download({:binary, archive.body},
        filename: archive.filename,
        content_type: "application/zip"
      )
    else
      {:error, reason} when reason in [:not_found, :not_stewarded, :authentication_required] ->
        raise SantoApiWeb.VehicleNotFound

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("The record could not be exported.")
    end
  end
end
