defmodule SantoApiWeb.HomeLiveTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Registry

  test "anonymous visitors get the club front door, not the directory", %{conn: conn} do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#club-home")
    assert has_element?(view, "#fresh-cars a[href='/v/#{vehicle.public_id}']")
    assert has_element?(view, "a[href='/start']", "Start your garage")
    assert has_element?(view, "#public-topbar a[href='/cars']", "Cars")
  end

  test "signed-in members go to the garage", %{conn: conn} do
    user = SantoApi.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/garage"}}} = live(conn, ~p"/")
  end
end
