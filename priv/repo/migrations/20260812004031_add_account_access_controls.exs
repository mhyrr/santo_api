defmodule SantoApi.Repo.Migrations.AddAccountAccessControls do
  @moduledoc """
  Current credential access plus its append-only operator audit trail.

  Suspension belongs to the account, not to a car: it blocks authentication
  while leaving every stewardship and ledger-attribution row untouched. The
  version is the stale-browser guard; it advances on both suspension and
  restoration, including when the visible state later returns to active.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :suspended_at, :utc_datetime_usec
      add :access_version, :integer, null: false, default: 0
    end

    create table(:account_access_decisions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :decided_by_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :action, :string, null: false
      add :reason, :text, null: false
      add :access_version, :integer, null: false
      add :decided_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:account_access_decisions, [:user_id])
    create index(:account_access_decisions, [:decided_by_user_id])

    create unique_index(:account_access_decisions, [:user_id, :access_version],
             name: :account_access_decisions_user_version_index
           )

    create constraint(:users, :users_access_version_nonnegative, check: "access_version >= 0")

    create constraint(:account_access_decisions, :account_access_decisions_valid_action,
             check: "action IN ('suspended', 'restored')"
           )

    create constraint(:account_access_decisions, :account_access_decisions_positive_version,
             check: "access_version > 0"
           )
  end
end
