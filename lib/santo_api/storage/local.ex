defmodule SantoApi.Storage.Local do
  @moduledoc """
  Artifact bytes on local disk, under the configured `:uploads_dir`.

  Fine for the operator bench and for development. Not acceptable once real
  owners upload documents — see `SantoApi.Storage`.
  """

  @behaviour SantoApi.Storage

  @impl true
  def put(ref, content) do
    dir = dir()
    File.mkdir_p!(dir)
    File.write(Path.join(dir, ref), content)
  end

  @impl true
  def fetch(ref) do
    File.read(Path.join(dir(), ref))
  end

  @impl true
  def exists?(ref) do
    File.exists?(Path.join(dir(), ref))
  end

  @doc """
  The directory bytes are written to.
  """
  def dir do
    Application.get_env(
      :santo_api,
      :uploads_dir,
      Path.join(to_string(:code.priv_dir(:santo_api)), "uploads")
    )
  end
end
