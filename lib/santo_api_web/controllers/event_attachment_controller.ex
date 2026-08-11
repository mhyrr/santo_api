defmodule SantoApiWeb.EventAttachmentController do
  @moduledoc """
  Serves an owner upload when it is attached to a public participation in the
  named event, or to the signed-in author's private participation.

  That join is the authorization boundary. A raw artifact id is never enough,
  and private entries remain available only through the owner surfaces.
  """

  use SantoApiWeb, :controller

  alias SantoApi.Media
  alias SantoApi.Events
  alias SantoApi.Storage

  def show(conn, %{"public_id" => event_public_id, "id" => attachment_id} = params) do
    with {:ok, attachment} <-
           Events.fetch_visible_attachment(
             conn.assigns.current_scope,
             event_public_id,
             attachment_id
           ),
         {:ok, delivery} <- delivery(attachment, params["variant"]),
         {:ok, bytes} <- Storage.fetch(delivery.storage_ref) do
      conn
      |> put_resp_content_type(delivery.mime, nil)
      |> put_resp_header("cache-control", cache_control(attachment.participation.visibility))
      |> maybe_download(attachment.kind)
      |> send_resp(200, bytes)
    else
      _unavailable -> raise SantoApiWeb.ArtifactNotFound
    end
  end

  defp delivery(%{kind: :photo, artifact: artifact}, variant),
    do: Media.variant(artifact, variant)

  defp delivery(%{artifact: %{storage_ref: ref, mime: mime}}, _variant) when is_binary(ref),
    do: {:ok, %{storage_ref: ref, mime: mime || "application/octet-stream"}}

  defp delivery(_attachment, _variant), do: {:error, :not_found}

  defp maybe_download(conn, kind) when kind in [:photo, :video], do: conn
  defp maybe_download(conn, _kind), do: put_resp_header(conn, "content-disposition", "attachment")

  defp cache_control(:public), do: "public, max-age=31536000, immutable"
  defp cache_control(:private), do: "private, no-store"
end
