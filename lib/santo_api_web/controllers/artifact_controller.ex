defmodule SantoApiWeb.ArtifactController do
  @moduledoc """
  Serves artifact bytes to the bench, and only to the bench.

  Whether we may serve an acquired document or an owner's photograph on a public
  page is an open rights question (owner_surface §9.3), so this route sits inside
  the operator scope with everything else at /bench. A possession proof is a
  picture of somebody's car, their VIN plate, and their handwriting; it is read
  by the person deciding the claim and by nobody else.

  Bytes come back through `SantoApi.Storage`, which validates the ref as a
  basename — a `storage_ref` joined onto a directory unchecked is how a path
  traversal happens.
  """

  use SantoApiWeb, :controller

  alias SantoApi.Registry
  alias SantoApi.Storage

  def show(conn, %{"id" => id}) do
    with {:ok, artifact} <- Registry.fetch_artifact(id),
         ref when is_binary(ref) <- artifact.storage_ref,
         {:ok, bytes} <- Storage.fetch(ref) do
      conn
      |> put_resp_content_type(artifact.mime || "application/octet-stream", nil)
      |> send_resp(200, bytes)
    else
      _unavailable -> raise SantoApiWeb.ArtifactNotFound
    end
  end
end
