defmodule SantoApiWeb.ArtifactNotFound do
  @moduledoc """
  Raised when an artifact has no row, or its bytes are not in the store we
  configured. Renders 404: a reference to a file we cannot produce is a missing
  file, not a broken server.
  """
  defexception message: "no artifact with that identifier", plug_status: 404
end
