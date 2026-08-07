defmodule SantoApi.Providers.Provider do
  @moduledoc """
  Contract for evidence acquisition providers.

  Providers own transport, source diagnostics, and acquisition metadata.
  They do not persist registry claims or decide which claim is true.
  """

  alias SantoApi.Providers.{Acquisition, Capability, Request}

  @type fulfillment :: :sync_api | :bulk_dataset | :async_order | :human_upload
  @type billing :: :free | :metered | :quoted
  @type access_class ::
          :open_data
          | :public_lookup
          | :public_record_order
          | :public_web
          | :owner_authorized
          | :licensed

  @type descriptor :: %{
          required(:id) => atom(),
          required(:name) => String.t(),
          required(:capabilities) => [Capability.t()],
          required(:identity_kinds) => [:vin | :chassis | :disputed],
          required(:required_selectors) => [atom()],
          required(:fulfillment) => fulfillment(),
          required(:billing) => billing(),
          required(:access_class) => access_class(),
          required(:documentation_url) => String.t()
        }

  @callback descriptor() :: descriptor()
  @callback supports?(Request.t()) :: :ok | {:error, term()}

  @callback acquire(Request.t()) ::
              {:ok, Acquisition.t()} | {:pending, map()} | {:error, term()}
end
