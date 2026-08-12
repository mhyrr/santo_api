defmodule SantoApi.AccountsSuspensionTest do
  use SantoApi.DataCase, async: true

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts
  alias SantoApi.Accounts.{Scope, UserToken}
  alias SantoApi.Bench
  alias SantoApi.Repo

  setup do
    operator = operator_fixture()
    user = user_fixture()

    %{operator_scope: Scope.for_user(operator), user: user}
  end

  test "suspension blocks retained session, magic-link, and MCP credentials until restoration",
       ctx do
    session_token = Accounts.generate_user_session_token(ctx.user)
    {magic_token, _digest} = generate_user_magic_link_token(ctx.user)
    {:ok, mcp_token, mcp_record} = Accounts.mint_mcp_token(ctx.user, "retained agent")

    assert Accounts.get_user_by_session_token(session_token)
    assert Accounts.get_user_by_magic_link_token(magic_token)
    assert {:ok, _scope} = Accounts.fetch_mcp_scope(mcp_token)

    assert {:ok, _suspended} =
             Bench.suspend_account(
               ctx.operator_scope,
               ctx.user.id,
               0,
               "Investigating a credential compromise."
             )

    refute Accounts.get_user_by_session_token(session_token)
    refute Accounts.get_user_by_magic_link_token(magic_token)
    assert {:error, :not_found} = Accounts.login_user_by_magic_link(magic_token)
    assert {:error, :invalid_token} = Accounts.fetch_mcp_scope(mcp_token)

    assert Repo.get_by!(UserToken, user_id: ctx.user.id, token: session_token)
    assert Repo.get!(UserToken, mcp_record.id)

    assert {:ok, _restored} =
             Bench.restore_account(
               ctx.operator_scope,
               ctx.user.id,
               1,
               "Account holder completed recovery."
             )

    assert Accounts.get_user_by_session_token(session_token)
    assert Accounts.get_user_by_magic_link_token(magic_token)
    assert {:ok, scope} = Accounts.fetch_mcp_scope(mcp_token)
    assert scope.user.id == ctx.user.id
  end

  test "a suspended account cannot request or receive a new login link", ctx do
    assert {:ok, _suspended} =
             Bench.suspend_account(
               ctx.operator_scope,
               ctx.user.id,
               0,
               "Temporarily block account access."
             )

    before = login_token_count(ctx.user.id)

    assert :ok = Accounts.request_login_link(ctx.user.email, &"https://example.test/#{&1}")

    assert {:error, :suspended} =
             Accounts.deliver_login_instructions(ctx.user, &"https://example.test/#{&1}")

    assert login_token_count(ctx.user.id) == before
  end

  test "the dormant password verifier also refuses a suspended credential", ctx do
    user = set_password(ctx.user)

    assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())

    assert {:ok, _suspended} =
             Bench.suspend_account(
               ctx.operator_scope,
               user.id,
               0,
               "Block every credential type, including the dormant password path."
             )

    refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
  end

  defp login_token_count(user_id) do
    Repo.aggregate(
      from(t in UserToken, where: t.user_id == ^user_id and t.context == "login"),
      :count
    )
  end
end
