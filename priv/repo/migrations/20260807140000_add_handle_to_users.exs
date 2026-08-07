defmodule SantoApi.Repo.Migrations.AddHandleToUsers do
  @moduledoc """
  The handle moves to registration, for every account (owner_surface §9.1,
  round 5). The user carries the *reservation*; the party is still minted
  with it at the first assertive act, so no placeholder ever enters a
  claim's `content_hash`. Nullable because accounts predating the rule are
  seed and test users — the party name, not this column, remains the
  ledger identity.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :handle, :string
    end

    create unique_index(:users, [:handle])
  end
end
