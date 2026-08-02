defmodule SantoApi.Storage do
  @moduledoc """
  Where artifact bytes live.

  Artifacts carry a `storage_ref` that is a basename and nothing else — no
  directory, no bucket, no host. That convention predates this module and is
  the reason moving to object storage is configuration rather than a migration
  (owner_surface.md §9.4): the rows do not know where the store is.

  `SantoApi.Storage.Local` writes to the configured `:uploads_dir` and is the
  adapter for the operator bench. Owner uploads — claiming photos, documents —
  are user data we cannot re-acquire, and they need an S3-compatible adapter
  before the first real owner. That adapter is not written yet; picking the
  provider is Greg's call (see the TODO in `config/runtime.exs`).

  Refs are validated as basenames on the way in and out. A `storage_ref` that
  reached the database from user-influenced input and then got joined onto a
  directory is exactly how a path traversal happens.
  """

  @type ref :: String.t()

  @callback put(ref(), binary()) :: :ok | {:error, term()}
  @callback fetch(ref()) :: {:ok, binary()} | {:error, term()}
  @callback exists?(ref()) :: boolean()

  @spec put(ref(), binary()) :: :ok | {:error, term()}
  def put(ref, content) when is_binary(content) do
    with :ok <- validate_ref(ref), do: adapter().put(ref, content)
  end

  @spec fetch(ref()) :: {:ok, binary()} | {:error, term()}
  def fetch(ref) do
    with :ok <- validate_ref(ref), do: adapter().fetch(ref)
  end

  @spec exists?(ref()) :: boolean()
  def exists?(ref) do
    validate_ref(ref) == :ok and adapter().exists?(ref)
  end

  @doc """
  The configured adapter module.
  """
  def adapter do
    Application.get_env(:santo_api, :storage_adapter, SantoApi.Storage.Local)
  end

  defp validate_ref(ref) when is_binary(ref) and ref != "" do
    if Path.basename(ref) == ref and ref not in [".", ".."] do
      :ok
    else
      {:error, :invalid_ref}
    end
  end

  defp validate_ref(_), do: {:error, :invalid_ref}
end
