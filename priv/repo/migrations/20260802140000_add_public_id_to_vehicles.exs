defmodule SantoApi.Repo.Migrations.AddPublicIdToVehicles do
  use Ecto.Migration

  @moduledoc """
  The canonical public URL keys the row, not the VIN (owner_surface §6, and
  contract §1: identity is an attribute and the page must survive an identity
  correction). `/vin/:vin` stays a resolver that redirects here.

  Backfilled per row rather than in SQL so existing links are minted by the same
  generator new ones are.
  """

  import Ecto.Query

  alias SantoApi.Repo

  def up do
    alter table(:vehicles) do
      add :public_id, :string
    end

    flush()

    for id <- Repo.all(from(v in "vehicles", select: v.id)) do
      Repo.update_all(
        from(v in "vehicles", where: v.id == ^id),
        set: [public_id: SantoApi.Registry.Vehicle.mint_public_id()]
      )
    end

    alter table(:vehicles) do
      modify :public_id, :string, null: false
    end

    create unique_index(:vehicles, [:public_id])
  end

  def down do
    drop unique_index(:vehicles, [:public_id])

    alter table(:vehicles) do
      remove :public_id
    end
  end
end
