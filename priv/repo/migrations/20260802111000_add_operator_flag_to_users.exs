defmodule SantoApi.Repo.Migrations.AddOperatorFlagToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :operator, :boolean, null: false, default: false
    end
  end
end
