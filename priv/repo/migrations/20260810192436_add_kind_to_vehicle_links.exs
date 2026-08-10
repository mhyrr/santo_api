defmodule SantoApi.Repo.Migrations.AddKindToVehicleLinks do
  use Ecto.Migration

  def change do
    alter table(:vehicle_links) do
      add :kind, :string, null: false, default: "other"
    end

    create constraint(:vehicle_links, :vehicle_links_kind_check,
             check: "kind IN ('other', 'build_thread')"
           )

    create unique_index(:vehicle_links, [:vehicle_id],
             where: "kind = 'build_thread'",
             name: :vehicle_links_one_build_thread_per_vehicle_index
           )
  end
end
