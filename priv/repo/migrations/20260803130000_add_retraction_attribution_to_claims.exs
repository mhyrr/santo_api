defmodule SantoApi.Repo.Migrations.AddRetractionAttributionToClaims do
  use Ecto.Migration

  # Retraction is its own act, so it gets its own attribution rather than
  # borrowing ratification's. A claim can be ratified and later retracted by
  # two different parties on two different days, and collapsing that into one
  # pair of columns would lose which happened.
  def change do
    alter table(:claims) do
      add :retracted_by_party_id,
          references(:parties, type: :binary_id, on_delete: :restrict)

      add :retracted_at, :utc_datetime_usec
    end
  end
end
