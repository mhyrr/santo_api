defmodule SantoApiWeb.ThemeLiveTest do
  use SantoApiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  test "renders the identity, foundations, shell states, controls, and domain components", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-page")
    assert has_element?(view, "#theme-identity")
    assert has_element?(view, "#theme-swatches .club-swatch", "Signal orange")
    assert has_element?(view, "#theme-topbar-anonymous")
    assert has_element?(view, "#theme-topbar-signed-in")
    assert has_element?(view, "#theme-avatars .club-avatar")
    assert has_element?(view, "#theme-controls #theme-odometer")
    assert has_element?(view, "#theme-car-card")
    assert has_element?(view, "#theme-log-entry")
    assert has_element?(view, "#theme-record-row")
  end

  test "the live top bar uses the anonymous navigation when signed out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-topbar a[href='/users/log-in']", "Sign in")
    assert has_element?(view, "#theme-topbar a[href='/start']", "Add a car")
    refute has_element?(view, "#theme-topbar .club-avatar-menu")
  end

  test "the live top bar uses the handle avatar when signed in", %{conn: conn} do
    user = user_fixture(%{handle: "grolsen"})

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/theme")

    assert has_element?(view, "#theme-topbar .club-avatar-menu")
    assert has_element?(view, "#theme-topbar .club-avatar[title='grolsen']", "G")
    assert has_element?(view, "#theme-topbar a[href='/users/settings']", "Settings")
    refute has_element?(view, "#theme-topbar a[href='/users/log-in']")
  end
end
