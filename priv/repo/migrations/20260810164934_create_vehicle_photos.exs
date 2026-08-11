defmodule SantoApi.Repo.Migrations.CreateVehiclePhotos do
  use Ecto.Migration

  def change do
    create table(:vehicle_photos, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict),
        null: false

      add :author_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :entry_ref, :uuid, null: false
      add :entry_date, :date, null: false
      add :alt_text, :string
      add :position, :integer, null: false, default: 0
      add :hero, :boolean, null: false, default: false
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:vehicle_photos, [:vehicle_id, :position])
    create index(:vehicle_photos, [:vehicle_id, :entry_ref])
    create index(:vehicle_photos, [:artifact_id])
    create index(:vehicle_photos, [:author_user_id])

    create unique_index(:vehicle_photos, [:vehicle_id],
             where: "hero = true",
             name: :vehicle_photos_one_hero_per_vehicle
           )

    create unique_index(:vehicle_photos, [:vehicle_id, :artifact_id, :entry_ref])

    create constraint(:vehicle_photos, :vehicle_photos_position_nonnegative,
             check: "position >= 0"
           )

    create constraint(:vehicle_photos, :vehicle_photos_visibility,
             check: "visibility IN ('public', 'private')"
           )
  end
end
