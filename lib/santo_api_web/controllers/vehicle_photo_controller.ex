defmodule SantoApiWeb.VehiclePhotoController do
  @moduledoc """
  Serves metadata-stripped car-photo derivatives through a vehicle placement.

  Anonymous callers may resolve public photos only after the car is published.
  An upload's author may also view their private placements, with a
  non-cacheable response. A later steward does not inherit that access.
  Original upload bytes never cross this public route.
  """

  use SantoApiWeb, :controller

  alias SantoApi.Media
  alias SantoApi.Owners.Photos
  alias SantoApi.Storage

  def show(conn, %{"public_id" => public_id, "id" => photo_id, "variant" => variant}) do
    with {:ok, photo} <- Photos.fetch_visible(conn.assigns.current_scope, public_id, photo_id),
         {:ok, derivative} <- Media.variant(photo.artifact, variant),
         {:ok, bytes} <- Storage.fetch(derivative.storage_ref) do
      conn
      |> put_resp_content_type(derivative.mime, nil)
      |> put_resp_header("cache-control", cache_control(photo.visibility))
      |> send_resp(200, bytes)
    else
      _unavailable -> raise SantoApiWeb.ArtifactNotFound
    end
  end

  defp cache_control(:public), do: "public, max-age=31536000, immutable"
  defp cache_control(:private), do: "private, no-store"
end
