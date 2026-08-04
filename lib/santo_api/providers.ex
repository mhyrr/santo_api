defmodule SantoApi.Providers do
  @moduledoc """
  Capability-based registry and entry point for evidence providers.

  The registry is intentionally static. Adding a provider is a reviewed
  code change because its billing, rights, and evidence semantics are
  product behavior.
  """

  alias SantoApi.Providers.{Capability, Request}

  @providers [SantoApi.Providers.Vpic]

  def all, do: @providers

  def ids, do: Enum.map(@providers, & &1.descriptor().id)

  def descriptors, do: Enum.map(@providers, & &1.descriptor())

  def provider(id) when is_atom(id) do
    case Enum.find(@providers, &(&1.descriptor().id == id)) do
      nil -> {:error, {:unknown_provider, id}}
      module -> {:ok, module}
    end
  end

  def provider(id), do: {:error, {:unknown_provider, id}}

  def for_capability(capability, identity) do
    with :ok <- Capability.validate(capability),
         {:ok, request} <- Request.new(capability, identity) do
      modules =
        Enum.filter(@providers, fn provider ->
          capability in provider.descriptor().capabilities and provider.supports?(request) == :ok
        end)

      {:ok, modules}
    end
  end

  def acquire(provider_id, %Request{} = request) do
    with {:ok, provider} <- provider(provider_id),
         :ok <- provider.supports?(request) do
      provider.acquire(request)
    end
  end
end
