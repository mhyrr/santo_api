defmodule SantoApi.Repo.Migrations.LinkUsersToParties do
  @moduledoc """
  The User↔Party link (owner_surface §5).

  The foreign key points from `users` to `parties`, not the other way around:
  the ledger must never depend on the auth system's shape. A party outlives its
  user account — every claim attributed to it is immutable — so `on_delete` is
  `:restrict`, and deleting a user leaves the party and its history standing.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :party_id, references(:parties, type: :binary_id, on_delete: :restrict)
    end

    # One party per user in both directions: two users sharing a party would
    # make "recorded by" ambiguous, and a claim cannot be un-attributed.
    create unique_index(:users, [:party_id])
  end
end
