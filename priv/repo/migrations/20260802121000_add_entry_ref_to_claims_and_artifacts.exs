defmodule SantoApi.Repo.Migrations.AddEntryRefToClaimsAndArtifacts do
  use Ecto.Migration

  @moduledoc """
  Entry grouping (owner_surface §2 "Entry grouping"): a nullable UUIDv7 shared
  by every claim and artifact born of one composed entry. A grouping tag, not
  an entry store — no table, no lifecycle, no state of its own.

  Existing rows stay null, which is what keeps the corpus content hashes still.
  """

  def change do
    alter table(:claims) do
      add :entry_ref, :uuid
    end

    alter table(:artifacts) do
      add :entry_ref, :uuid
    end

    create index(:claims, [:entry_ref], where: "entry_ref IS NOT NULL")
    create index(:artifacts, [:entry_ref], where: "entry_ref IS NOT NULL")
  end
end
