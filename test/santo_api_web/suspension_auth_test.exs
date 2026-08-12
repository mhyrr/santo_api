defmodule SantoApiWeb.SuspensionAuthTest do
  use SantoApiWeb.ConnCase, async: true

  import SantoApi.AccountsFixtures

  alias Phoenix.LiveView
  alias SantoApi.Accounts
  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApiWeb.UserAuth

  setup %{conn: conn} do
    operator = operator_fixture()
    user = user_fixture()
    session_token = Accounts.generate_user_session_token(user)
    {:ok, mcp_token, _record} = Accounts.mint_mcp_token(user, "existing agent")

    assert {:ok, _suspended} =
             Bench.suspend_account(
               Scope.for_user(operator),
               user.id,
               0,
               "Block the credential on every authenticated surface."
             )

    conn =
      conn
      |> Map.replace!(:secret_key_base, SantoApiWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{conn: conn, user: user, session_token: session_token, mcp_token: mcp_token}
  end

  test "an existing browser session cannot load an authenticated route", ctx do
    conn = ctx.conn |> put_session(:user_token, ctx.session_token) |> get(~p"/garage")

    assert redirected_to(conn) == ~p"/users/log-in"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "You must log in to access this page."
  end

  test "a LiveView reconnect with the old session is rejected", ctx do
    session = ctx.conn |> put_session(:user_token, ctx.session_token) |> get_session()

    socket = %LiveView.Socket{
      endpoint: SantoApiWeb.Endpoint,
      assigns: %{__changed__: %{}, flash: %{}}
    }

    assert {:halt, updated_socket} =
             UserAuth.on_mount(:require_authenticated, %{}, session, socket)

    assert updated_socket.assigns.current_scope == nil
  end

  test "the retained MCP token receives the normal unauthorized response", ctx do
    conn =
      ctx.conn
      |> put_req_header("authorization", "Bearer " <> ctx.mcp_token)
      |> put_req_header("content-type", "application/json")
      |> post(~p"/mcp", %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})

    assert response(conn, 401) == "Unauthorized"
    assert [header] = get_resp_header(conn, "www-authenticate")
    assert header =~ "Bearer"
  end
end
