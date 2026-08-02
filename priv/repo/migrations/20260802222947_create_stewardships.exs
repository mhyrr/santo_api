defmodule SantoApi.Repo.Migrations.CreateStewardships do
  @moduledoc """
  Who maintains which car (owner_surface §4 step 5).

  Authorization, not registry truth: nothing here asserts ownership, and no
  claim is written when a stewardship is granted. Rows never delete — revocation
  is a status flip with a reason, because entries logged under a stewardship stay
  in the ledger and the record of what authorized them has to stay too.
  """

  use Ecto.Migration

  def change do
    create table(:stewardships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false

      # The possession proof that justified the grant (§4 step 3). Null on a
      # grant made out of band, which is every grant until the claiming flow
      # ships — the column records evidence, it does not manufacture it.
      add :proof_artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)

      add :status, :string, null: false, default: "active"
      add :reason, :text
      add :decided_by_user_id, references(:users, type: :binary_id, on_delete: :restrict)
      add :decided_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:stewardships, [:user_id])
    create index(:stewardships, [:vehicle_id])

    # One active steward per car. A second person claiming a stewarded vehicle
    # is a contested claim an operator adjudicates (§4), not a second row — and
    # a race that produced two silent stewards of one page would be worse than
    # the error the caller gets here.
    create unique_index(:stewardships, [:vehicle_id],
             where: "status = 'active'",
             name: :stewardships_active_vehicle_index
           )
  end
end
