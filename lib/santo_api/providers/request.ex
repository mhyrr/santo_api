defmodule SantoApi.Providers.Request do
  @moduledoc """
  One capability request against one normalized Santo identity.

  `selectors` are reusable source locators, validated independently of any
  vendor. `options` are capability-specific behavior knobs. Credentials and
  billing authorization belong in runtime configuration, not in this value or
  in persisted artifacts.
  """

  alias SantoApi.Providers.{Capability, Selector}

  @enforce_keys [:capability, :identity]
  defstruct [:capability, :identity, selectors: %Selector{}, options: %{}]

  @type identity ::
          {:vin, String.t()}
          | {:chassis, term(), term(), String.t()}
          | {:disputed, [term()], [term()]}

  @type t :: %__MODULE__{
          capability: Capability.t(),
          identity: identity(),
          selectors: Selector.t(),
          options: map()
        }

  def new(capability, identity), do: new(capability, identity, %Selector{}, %{})

  def new(capability, identity, %Selector{} = selectors),
    do: new(capability, identity, selectors, %{})

  def new(capability, identity, selectors) when is_map(selectors) do
    with {:ok, selector} <- Selector.new(selectors) do
      new(capability, identity, selector, %{})
    end
  end

  def new(_capability, _identity, _selectors), do: {:error, :invalid_selectors}

  def new(capability, identity, %Selector{} = selectors, options) when is_map(options) do
    with :ok <- Capability.validate(capability),
         :ok <- validate_identity(identity),
         :ok <- Selector.validate(selectors) do
      {:ok,
       %__MODULE__{
         capability: capability,
         identity: identity,
         selectors: selectors,
         options: options
       }}
    end
  end

  def new(_capability, _identity, _selectors, _options), do: {:error, :invalid_options}

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
