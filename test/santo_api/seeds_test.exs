defmodule SantoApi.SeedsTest do
  use SantoApi.DataCase, async: false

  import ExUnit.CaptureIO
  import SantoApi.AccountsFixtures, only: [unique_user_handle: 0]

  alias SantoApi.Accounts
  alias SantoApi.Accounts.User

  @seeds Path.expand("../../priv/repo/seeds.exs", __DIR__)

  defp run_seeds, do: capture_io(fn -> Code.eval_file(@seeds) end)

  setup do
    email = "seed-#{System.unique_integer([:positive])}@example.com"
    System.put_env("SEED_OPERATOR_EMAIL", email)
    on_exit(fn -> System.delete_env("SEED_OPERATOR_EMAIL") end)
    %{email: email}
  end

  test "creates a confirmed operator", %{email: email} do
    run_seeds()

    user = Accounts.get_user_by_email(email)

    assert %User{} = user
    assert user.operator
    assert user.confirmed_at
  end

  test "is re-runnable — a second pass neither duplicates nor demotes", %{email: email} do
    run_seeds()
    first = Accounts.get_user_by_email(email)

    run_seeds()
    second = Accounts.get_user_by_email(email)

    assert second.id == first.id
    assert second.operator
    assert Repo.aggregate(from(u in User, where: u.email == ^email), :count) == 1
  end

  test "promotes an account that already exists without the flag", %{email: email} do
    {:ok, user} = Accounts.register_user(%{email: email, handle: unique_user_handle()})
    refute user.operator

    run_seeds()

    assert Accounts.get_user_by_email(email).operator
  end
end
