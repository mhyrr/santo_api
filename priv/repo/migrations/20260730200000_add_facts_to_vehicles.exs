defmodule SantoApi.Repo.Migrations.AddFactsToVehicles do
  use Ecto.Migration

  def change do
    alter table(:vehicles) do
      add :facts, :map, null: false, default: %{}
    end
  end
end
