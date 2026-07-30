defmodule SantoApi.Providers.Acquisition do
  @moduledoc """
  An answered provider lookup before persistence as an evidence artifact.

  Coverage describes the provider's answer, not the vehicle. In
  particular, `:none` means "this provider returned no coverage at this
  time"; it never means clean history.
  """

  alias SantoApi.Providers.Capability

  @type coverage :: :complete | :partial | :none | :unknown

  @enforce_keys [
    :provider,
    :capability,
    :coverage,
    :payload,
    :source_url,
    :media_type,
    :acquired_at,
    :rights_profile
  ]
  defstruct [
    :provider,
    :capability,
    :coverage,
    :payload,
    :source_url,
    :media_type,
    :acquired_at,
    :rights_profile,
    diagnostics: %{}
  ]

  @type t :: %__MODULE__{
          provider: atom(),
          capability: Capability.t(),
          coverage: coverage(),
          payload: term(),
          source_url: String.t(),
          media_type: String.t(),
          acquired_at: DateTime.t(),
          rights_profile: String.t(),
          diagnostics: map()
        }
end
