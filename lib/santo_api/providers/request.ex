defmodule SantoApi.Providers.Request do
  @moduledoc """
  One capability request against one normalized Santo identity.

  `options` are provider-neutral request constraints. Credentials and
  billing authorization belong in runtime configuration, not in this
  value or in persisted artifacts.
  """

  alias SantoApi.Providers.Capability

  @enforce_keys [:capability, :identity]
  defstruct [:capability, :identity, options: %{}]

  @type identity ::
          {:vin, String.t()}
          | {:chassis, term(), term(), String.t()}
          | {:disputed, [term()], [term()]}

  @type t :: %__MODULE__{
          capability: Capability.t(),
          identity: identity(),
          options: map()
        }

  def new(capability, identity, options \\ %{}) when is_map(options) do
    with :ok <- Capability.validate(capability),
         :ok <- validate_identity(identity) do
      {:ok, %__MODULE__{capability: capability, identity: identity, options: options}}
    end
  end

  def new(_capability, _identity, _options), do: {:error, :invalid_options}

  def identity_kind(%__MODULE__{identity: identity}), do: identity_kind(identity)
  def identity_kind({:vin, _vin}), do: :vin
  def identity_kind({:chassis, _marque, _era, _number}), do: :chassis
  def identity_kind({:disputed, _candidates, _requirements}), do: :disputed
  def identity_kind(_identity), do: :unknown

  defp validate_identity({:vin, vin}) when is_binary(vin) and vin != "", do: :ok

  defp validate_identity({:chassis, _marque, _era, number})
       when is_binary(number) and number != "",
       do: :ok

  defp validate_identity({:disputed, candidates, requirements})
       when is_list(candidates) and is_list(requirements),
       do: :ok

  defp validate_identity(identity), do: {:error, {:invalid_identity, identity}}
end
