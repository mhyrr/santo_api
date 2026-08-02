defmodule SantoApi.Repo.Migrations.AddVisibilityToClaimsAndArtifacts do
  use Ecto.Migration

  @moduledoc """
  Presentation state, not ledger state (owner_surface §6): mutable, excluded
  from `content_hash`, no effect on admission or tier. A private row still
  exists in the ledger, still counts, and still appears in the owner's own view.

  Default is `public` on both tables. The per-kind refinement the design floats
  — uploaded documents private, entries public — is §6 open decision 4 and is
  not settled; nothing renders visibility yet, so the default is still cheap
  to move.
  """

  def change do
    alter table(:claims) do
      add :visibility, :string, null: false, default: "public"
    end

    alter table(:artifacts) do
      add :visibility, :string, null: false, default: "public"
    end
  end
end
