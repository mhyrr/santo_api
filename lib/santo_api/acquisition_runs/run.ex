defmodule SantoApi.AcquisitionRuns.Run do
  @moduledoc """
  One durable attempt to build the public record for a vehicle.

  The run records product state. Oban records how executable work is leased,
  retried, and recovered; those mechanics deliberately do not leak into this
  schema.
  """

  use Ecto.Schema

  alias SantoApi.Accounts.User
  alias SantoApi.AcquisitionRuns.Step
  alias SantoApi.Registry.Vehicle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "acquisition_runs" do
    belongs_to :vehicle, Vehicle
    belongs_to :initiated_by_user, User
    has_many :steps, Step

    field :policy, Ecto.Enum, values: [:free_public_v1]
    field :status, Ecto.Enum, values: [:pending, :running, :complete], default: :pending
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
