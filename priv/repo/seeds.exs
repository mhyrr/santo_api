# Script for populating the database. Run directly with:
#
#     mix run priv/repo/seeds.exs
#
# It also runs as part of `mix ecto.setup` and `mix ecto.reset`.
#
# Seeds are re-runnable and idempotent, like the corpus scripts: a second pass
# reports what already exists rather than duplicating or resetting it.

alias SantoApi.Accounts
alias SantoApi.Accounts.User
alias SantoApi.Repo

# The operator account. There is no self-serve path to the operator flag —
# /bench is behind it, and this is how the first one comes into being.
# Override with SEED_OPERATOR_EMAIL to seed a different address.
operator_email = System.get_env("SEED_OPERATOR_EMAIL", "grolsen@gmail.com")

{user, verb} =
  case Accounts.get_user_by_email(operator_email) do
    %User{} = user -> {user, "found"}
    nil -> {Repo.insert!(User.email_changeset(%User{}, %{email: operator_email})), "created"}
  end

# Confirmed up front so it reads as a settled account rather than one that
# flips state on first login. Logging in is still a magic link — there is no
# password to seed (owner_surface.md §5).
user = if user.confirmed_at, do: user, else: Repo.update!(User.confirm_changeset(user))

{:ok, user} = if user.operator, do: {:ok, user}, else: Accounts.set_operator(user, true)

IO.puts("operator #{verb}: #{user.email} (operator: #{user.operator})")
