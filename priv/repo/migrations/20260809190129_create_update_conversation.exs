defmodule SantoApi.Repo.Migrations.CreateUpdateConversation do
  use Ecto.Migration

  def change do
    create table(:update_likes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :entry_ref, :uuid, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:update_likes, [:vehicle_id, :entry_ref, :user_id])
    create index(:update_likes, [:vehicle_id, :entry_ref])

    create table(:update_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vehicle_id, references(:vehicles, type: :binary_id, on_delete: :restrict), null: false
      add :entry_ref, :uuid, null: false

      add :author_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :author_handle, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "visible"
      add :withdrawn_at, :utc_datetime_usec
      add :hidden_at, :utc_datetime_usec
      add :hidden_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :moderation_note, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:update_comments, [:vehicle_id, :entry_ref, :inserted_at])
    create index(:update_comments, [:author_user_id])

    create table(:comment_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :comment_id, references(:update_comments, type: :binary_id, on_delete: :delete_all),
        null: false

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

    create unique_index(:comment_reports, [:comment_id, :reporter_user_id])
    create index(:comment_reports, [:status, :inserted_at])
  end
end
