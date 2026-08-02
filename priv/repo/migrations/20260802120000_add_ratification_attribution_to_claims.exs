defmodule SantoApi.Repo.Migrations.AddRatificationAttributionToClaims do
  use Ecto.Migration

  @moduledoc """
  The contract calls ratification "one state flip with who and when attached"
  (evidence_contract §8), but the who and when were never built — the only
  ratifier was the bench. Owner self-ratification (owner_surface §3) makes them
  mandatory.

  Backfill covers claims that actually passed through the gate: `:santo` claims
  are born `:admitted` and were never ratified by anyone, so stamping them would
  assert a ratification that never happened.
  """

  def up do
    alter table(:claims) do
      add :ratified_by_party_id, references(:parties, type: :binary_id, on_delete: :restrict)
      add :ratified_at, :utc_datetime_usec
    end

    create index(:claims, [:ratified_by_party_id])

    execute("""
    UPDATE claims
       SET ratified_by_party_id = parties.id,
           ratified_at = claims.inserted_at
      FROM parties
     WHERE parties.name = 'Vin Santo'
       AND parties.kind = 'vin_santo'
       AND claims.method <> 'santo'
       AND claims.state IN ('admitted', 'rejected')
    """)
  end

  def down do
    alter table(:claims) do
      remove :ratified_by_party_id
      remove :ratified_at
    end
  end
end
