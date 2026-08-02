defmodule SantoApi.Repo.Migrations.AddCurrentStateToVehicles do
  use Ecto.Migration

  @moduledoc """
  The second projection (owner_surface §2b): `facts` answers what the factory
  built, `current_state` answers what the car is now. Sibling to `facts`, never
  computed from it — for a swapped car the factory column is thin and current
  state is nearly the whole record.

  Derived and replayable, so no backfill: the fold recomputes from the ledger
  the next time a claim is written, and `Registry.refresh_projections/1`
  rebuilds it on demand.
  """

  def change do
    alter table(:vehicles) do
      add :current_state, :map, null: false, default: "{}"
    end
  end
end
