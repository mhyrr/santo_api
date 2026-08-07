defmodule SantoApi.Providers.Capability do
  @moduledoc """
  The closed vocabulary of questions an evidence provider can answer.

  Capabilities describe the question, not the vendor. Provider selection
  and claim interpretation both depend on this distinction.
  """

  @type t ::
          :vin_identity
          | :generic_specifications
          | :factory_build
          | :title_history
          | :odometer_history
          | :total_loss_history
          | :theft_status
          | :accident_history
          | :service_history
          | :inspection
          | :recall_campaigns
          | :technical_bulletins
          | :open_recall_status
          | :listing_history
          | :auction_history

  @capabilities [
    :vin_identity,
    :generic_specifications,
    :factory_build,
    :title_history,
    :odometer_history,
    :total_loss_history,
    :theft_status,
    :accident_history,
    :service_history,
    :inspection,
    :recall_campaigns,
    :technical_bulletins,
    :open_recall_status,
    :listing_history,
    :auction_history
  ]

  def all, do: @capabilities

  def valid?(capability), do: capability in @capabilities

  def validate(capability) do
    if valid?(capability), do: :ok, else: {:error, {:unknown_capability, capability}}
  end
end
