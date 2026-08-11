defmodule SantoApiWeb.DistributionController do
  @moduledoc "Serves the two named public distribution transforms."

  use SantoApiWeb, :controller

  alias SantoApi.{Distribution, Owners, Registry}
  alias SantoApiWeb.DistributionPresenter

  def share_card(conn, %{"public_id" => public_id, "entry_ref" => entry_ref}) do
    with {:ok, vehicle} <- Registry.fetch_by_public_id(public_id),
         true <- Owners.published?(vehicle),
         {:ok, entry} <- Owners.fetch_timeline_entry(nil, vehicle, entry_ref),
         payload = DistributionPresenter.entry(vehicle, entry),
         {:ok, bytes} <- Distribution.share_card(payload) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "public, max-age=300")
      |> put_resp_header("content-disposition", ~s(inline; filename="#{payload.download_name}"))
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, bytes)
    else
      _not_public -> send_resp(conn, 404, "Not found")
    end
  end

  def badge(conn, %{"public_id" => public_id}) do
    with {:ok, vehicle} <- Registry.fetch_by_public_id(public_id),
         true <- Owners.published?(vehicle) do
      svg = vehicle |> DistributionPresenter.vehicle() |> Distribution.badge_svg()

      conn
      |> put_resp_content_type("image/svg+xml", nil)
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, svg)
    else
      _not_public -> send_resp(conn, 404, "Not found")
    end
  end
end
