defmodule SantoApi.Repo.Migrations.CreatePossessionChallenges do
  @moduledoc """
  Proof of possession, in flight (owner_surface §4 steps 1–4).

  One row is one person's attempt to claim one car: the code they were given,
  the photo they took of the VIN plate with that code in frame, and the
  operator's decision. Decided rows stay — a stewardship's justification has to
  be readable later, and a denial is the record of a claim we turned down.

  The code carries the property the flow rests on: it did not exist when a
  stranger photographed the car at a show, so a pre-existing photo cannot
  satisfy it. That holds only while the code is fresh, hence the expiry.
  """

  use Ecto.Migration

  def change do
    create table(:possession_challenges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      add :code, :string, null: false
      add :status, :string, null: false, default: "issued"
      add :expires_at, :utc_datetime_usec, null: false

      # The handle the claimant chose, held until there is a party to name.
      # Permanent once minted (§9.1), so it is settled before the code goes out
      # rather than asked for at the operator's desk.
      add :handle, :string

      add :proof_artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)
      add :reason, :text
      add :decided_by_user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :decided_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:possession_challenges, [:vehicle_id])
    create index(:possession_challenges, [:status])

    # One live challenge per person per car (§4 step 2). Two codes for one pair
    # would mean a photo that satisfies neither and an operator comparing
    # against the wrong one.
    create unique_index(:possession_challenges, [:user_id, :vehicle_id],
             where: "status in ('issued', 'submitted')",
             name: :possession_challenges_live_index
           )
  end
end
