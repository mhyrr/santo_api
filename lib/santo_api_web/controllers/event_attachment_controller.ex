defmodule SantoApiWeb.EventAttachmentController do
  @moduledoc """
  Serves an owner upload only when it is attached to a public participation in
  the public event named by the route.

  That join is the authorization boundary. A raw artifact id is never enough,
  and private entries remain available only through the owner surfaces.
  """

  use SantoApiWeb, :controller

  alias SantoApi.Events
  alias SantoApi.Storage

  def show(conn, %{"public_id" => event_public_id, "id" => attachment_id}) do
    with {:ok, attachment} <- Events.fetch_public_attachment(event_public_id, attachment_id),
         ref when is_binary(ref) <- attachment.artifact.storage_ref,
         {:ok, bytes} <- Storage.fetch(ref) do
      conn
      |> put_resp_content_type(attachment.artifact.mime || "application/octet-stream", nil)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> maybe_download(attachment.kind)
      |> send_resp(200, bytes)
    else
      _unavailable -> raise SantoApiWeb.ArtifactNotFound
    end
  end

  defp maybe_download(conn, kind) when kind in [:photo, :video], do: conn
  defp maybe_download(conn, _kind), do: put_resp_header(conn, "content-disposition", "attachment")
end
