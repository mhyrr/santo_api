defmodule SantoApiWeb.UserLive.LoginTest do
  use SantoApiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "Log in"
      assert html =~ "Sign up"
      assert html =~ "Log in with email"
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"

      assert SantoApi.Repo.get_by!(SantoApi.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")

      assert html =~ "If your email is in our system"
    end

    test "stops sending once an address has had its share of links", %{conn: conn} do
      user = user_fixture()
      {limit, _window} = SantoApi.RateLimit.limits(:login_email)

      send_link = fn ->
        {:ok, lv, _html} = live(conn, ~p"/users/log-in")

        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")
      end

      for _ <- 1..limit, do: {:ok, _lv, _html} = send_link.()

      before = token_count(user)
      {:ok, _lv, html} = send_link.()

      # Same reply either way — the limit must not become an oracle for which
      # addresses are registered.
      assert html =~ "If your email is in our system"
      assert token_count(user) == before
    end

    test "the limit is per address, not shared across them", %{conn: conn} do
      {limit, _window} = SantoApi.RateLimit.limits(:login_email)
      spender = user_fixture()
      bystander = user_fixture()

      for _ <- 1..(limit + 1) do
        {:ok, lv, _html} = live(conn, ~p"/users/log-in")

        form(lv, "#login_form_magic", user: %{email: spender.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log-in")
      end

      before = token_count(bystander)

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form(lv, "#login_form_magic", user: %{email: bystander.email})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

      assert token_count(bystander) == before + 1
    end
  end

  defp token_count(user) do
    import Ecto.Query

    SantoApi.Repo.aggregate(
      from(t in SantoApi.Accounts.UserToken,
        where: t.user_id == ^user.id and t.context == "login"
      ),
      :count
    )
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Sign up")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/log-in")

      assert html =~ "You need to reauthenticate"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert has_element?(lv, "#user_email[value='#{user.email}'][readonly]")
    end
  end
end
