defmodule SantoApi.Repo.Migrations.AddMcpTokenColumns do
  use Ecto.Migration

  # An MCP token is a `users_tokens` row in the "mcp" context — the same
  # hashed-token-with-context machine phx.gen.auth already ships, extended by
  # the two columns a long-lived credential needs that a login link does not:
  # a name, so a user can tell two tokens apart when revoking one, and a
  # last-used stamp, so a leaked token is noticeable (owner_surface §9.1).
  def change do
    alter table(:users_tokens) do
      add :name, :string
      add :last_used_at, :utc_datetime
    end
  end
end
