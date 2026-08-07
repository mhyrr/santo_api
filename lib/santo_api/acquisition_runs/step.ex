defmodule SantoApi.AcquisitionRuns.Step do
  @moduledoc """
  A user-facing step in an acquisition run.

  Provider and capability values are Ecto enums: they are stored as strings,
  while reads can only produce atoms from the reviewed, closed registries.
  """

  use Ecto.Schema

  alias SantoApi.AcquisitionRuns.Run
  alias SantoApi.Providers
  alias SantoApi.Providers.Capability
  alias SantoApi.Registry.Artifact

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @providers Providers.ids()
  @capabilities Capability.all()

  schema "acquisition_steps" do
    belongs_to :run, Run
    belongs_to :artifact, Artifact
    belongs_to :depends_on_step, __MODULE__

    field :step_key, :string
    field :position, :integer
    field :kind, Ecto.Enum, values: [:santo_decode, :provider, :gap]
    field :provider, Ecto.Enum, values: @providers
    field :capability, Ecto.Enum, values: @capabilities

    field :status, Ecto.Enum,
      values: [:pending, :running, :complete, :no_record, :needs_input, :failed, :unsupported]

    field :attempt_count, :integer, default: 0
    field :missing_selectors, {:array, :string}, default: []
    field :conflicted_selectors, {:array, :string}, default: []
    field :selectors, :map, default: %{}
    field :diagnostics, :map, default: %{}
    field :last_error, :map
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
