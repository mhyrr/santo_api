defmodule SantoApi.Vpic do
  @moduledoc """
  Compatibility facade for the NHTSA vPIC provider.

  New provider routing uses `SantoApi.Providers.Vpic`; registry and API
  callers retain this module while that migration is staged.
  """

  defdelegate descriptor(), to: SantoApi.Providers.Vpic
  defdelegate supports?(request), to: SantoApi.Providers.Vpic
  defdelegate acquire(request), to: SantoApi.Providers.Vpic
  defdelegate fetch(vin), to: SantoApi.Providers.Vpic
  defdelegate facts(values), to: SantoApi.Providers.Vpic
end
