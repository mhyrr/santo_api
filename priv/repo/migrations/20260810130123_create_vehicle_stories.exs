defmodule SantoApi.Repo.Migrations.CreateVehicleStories do
  use Ecto.Migration

  def change do
    create table(:vehicle_stories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :author_user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :tagline, :string, null: false
      add :body, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:vehicle_stories, [:vehicle_id])
    create index(:vehicle_stories, [:author_user_id])
  end
end
