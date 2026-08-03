defmodule SantoApiWeb.UserSettingsMcpTest do
  @moduledoc """
  The token half of account settings (owner_surface §9.1).

  What matters on this page is the shown-once rule: the plaintext appears in
  the response that mints it and never again, on any later render.
  """

  use SantoApiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  describe "the token list" do
    test "says what the surface is for when there are no tokens", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Assistant access"
      refute html =~ "Revoke"
    end

    test "lists a token by name without any credential material", %{conn: conn, user: user} do
      {:ok, plaintext, _record} = Accounts.mint_mcp_token(user, "laptop")

      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "laptop"
      assert html =~ "Never used"
      refute html =~ plaintext
    end
  end

  describe "minting" do
    test "shows the plaintext once and never on a later render", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      minted =
        lv
        |> form("#mcp_token_form", %{token: %{name: "laptop"}})
        |> render_submit()

      assert minted =~ "laptop"
      assert [%{name: "laptop"}] = Accounts.list_mcp_tokens(user_from(lv))

      # The token appears in the mint response, so pull it back out and prove
      # a fresh mount cannot show it again.
      {:ok, _lv2, later} = live(conn, ~p"/users/settings")
      refute later =~ shown_token(minted)
    end

    test "refuses an unnamed token", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#mcp_token_form", %{token: %{name: ""}})
        |> render_submit()

      assert html =~ "Name this token"
    end
  end

  describe "revoking" do
    test "removes the token and stops it working", %{conn: conn, user: user} do
      {:ok, plaintext, record} = Accounts.mint_mcp_token(user, "laptop")
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html = lv |> element(~s{button[phx-value-id="#{record.id}"]}) |> render_click()

      refute html =~ "laptop"
      assert {:error, :invalid_token} = Accounts.fetch_mcp_scope(plaintext)
    end
  end

  defp user_from(lv), do: :sys.get_state(lv.pid).socket.assigns.current_scope.user

  # The minted plaintext is rendered inside a readonly input; pull it back out
  # so the "never again" assertion is about the real credential.
  defp shown_token(html) do
    [[_, token]] = Regex.scan(~r/id="minted-token"[^>]*value="([^"]+)"/, html)
    token
  end
end
