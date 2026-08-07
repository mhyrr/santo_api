defmodule SantoApi.Repo.Migrations.CreateVehicleLinks do
  @moduledoc """
  Owner-curated pointers to where a car lives elsewhere — a build thread, a
  YouTube channel, an Instagram account (owner_surface §7b.1 decision 8, §9.3).

  Presentation only: no claim, no artifact, no content hash. Links are mutable
  and deletable, unlike the ledger they sit beside — that asymmetry is the
  point, not an oversight (see `SantoApi.Owners.VehicleLink` moduledoc).
  """

  use Ecto.Migration

  def change do
    create table(:vehicle_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :delete_all),
        null: false

      add :url, :string, null: false
      add :label, :string
      # Display order the owner chose, not insertion order — a fresh link
      # appends at the end rather than reshuffling what's already on the page.
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:vehicle_links, [:vehicle_id, :position])
  end
end
