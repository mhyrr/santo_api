defmodule SantoApi.Repo.Migrations.AddContentReporting do
  use Ecto.Migration

  def change do
    alter table(:vehicles) do
      add :visibility, :string, null: false, default: "public"
    end

    create constraint(:vehicles, :vehicles_visibility,
             check: "visibility IN ('public', 'private')"
           )

    create table(:content_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :target_kind, :string, null: false
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :entry_ref, :uuid
      add :reporter_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reporter_handle, :string, null: false
      add :reason, :string, null: false
      add :detail, :text
      add :status, :string, null: false, default: "open"
      add :decided_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :decided_at, :utc_datetime_usec
      add :decision_note, :text
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:content_reports, :content_reports_target,
             check:
               "(target_kind = 'vehicle' AND entry_ref IS NULL) OR " <>
                 "(target_kind = 'entry' AND entry_ref IS NOT NULL)"
           )

    create constraint(:content_reports, :content_reports_reason,
             check: "reason IN ('abuse', 'doxxing', 'fraud', 'other')"
           )

    create constraint(:content_reports, :content_reports_status,
             check: "status IN ('open', 'dismissed', 'actioned')"
           )

    create unique_index(:content_reports, [:vehicle_id, :reporter_user_id],
             where: "entry_ref IS NULL",
             name: :content_reports_vehicle_reporter_index
           )

    create unique_index(:content_reports, [:vehicle_id, :entry_ref, :reporter_user_id],
             where: "entry_ref IS NOT NULL",
             name: :content_reports_entry_reporter_index
           )

    create index(:content_reports, [:status, :inserted_at])
    create index(:content_reports, [:vehicle_id, :entry_ref])
  end
end
