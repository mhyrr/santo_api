defmodule SantoApi.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:event_occurrences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :public_id, :string, null: false

      add :creator_user_id, references(:users, type: :binary_id, on_delete: :restrict),
        null: false

      add :title, :string, null: false
      add :starts_on, :date, null: false
      add :ends_on, :date
      add :starts_at, :time
      add :ends_at, :time
      add :timezone, :string
      add :place_text, :string, null: false
      add :description, :text
      add :tags, {:array, :string}, null: false, default: []
      add :source_status, :string, null: false, default: "community"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_occurrences, [:public_id])
    create index(:event_occurrences, [:starts_on])
    create index(:event_occurrences, [:creator_user_id])

    create constraint(:event_occurrences, :event_occurrences_date_order,
             check: "ends_on IS NULL OR ends_on >= starts_on"
           )

    create constraint(:event_occurrences, :event_occurrences_source_status,
             check: "source_status IN ('community', 'organizer', 'imported')"
           )

    create table(:event_participations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_id,
          references(:event_occurrences, type: :binary_id, on_delete: :delete_all),
          null: false

      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :entry_ref, :uuid, null: false
      add :journal, :text, null: false
      add :tags, {:array, :string}, null: false, default: []
      add :details, :map, null: false, default: fragment("'[]'::jsonb")
      add :visibility, :string, null: false, default: "public"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_participations, [:event_id, :vehicle_id])
    create unique_index(:event_participations, [:vehicle_id, :entry_ref])
    create index(:event_participations, [:event_id, :inserted_at])
    create index(:event_participations, [:user_id])

    create constraint(:event_participations, :event_participations_visibility,
             check: "visibility IN ('public', 'private')"
           )

    create table(:event_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :participation_id,
          references(:event_participations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :artifact_id, references(:artifacts, type: :binary_id, on_delete: :restrict)
      add :url, :text
      add :label, :string, null: false
      add :kind, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:event_attachments, [:participation_id, :position])
    create index(:event_attachments, [:artifact_id], where: "artifact_id IS NOT NULL")

    create constraint(:event_attachments, :event_attachments_one_target,
             check:
               "(artifact_id IS NOT NULL AND url IS NULL) OR (artifact_id IS NULL AND url IS NOT NULL)"
           )

    create constraint(:event_attachments, :event_attachments_kind,
             check: "kind IN ('photo', 'video', 'link', 'file')"
           )
  end
end
