defmodule SantoApiWeb.EntryDeleteTest do
  @moduledoc """
  Removing an entry from the car's page (owner_surface §8, decided 2026-08-03).

  The web half of correction. The control appears on entries the caller
  asserted and nowhere else: not on a visitor's view, and not on entries the
  registry or a previous steward wrote.
  """

  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "mhyrr"})
    {:ok, _} = Owners.grant_stewardship(user, vehicle)
    scope = Scope.for_user(user)

    {:ok, entry} =
      Owners.compose_entry(scope, vehicle, %{
        date: ~D[2026-08-02],
        claims: [%{predicate: "observation.mileage", value: 41_660}]
      })

    %{vehicle: vehicle, user: user, scope: scope, entry: entry}
  end

  test "the steward can remove their own entry from the page", ctx do
    conn = log_in_user(build_conn(), ctx.user)
    {:ok, lv, html} = live(conn, ~p"/v/#{ctx.vehicle.public_id}")

    assert html =~ "41,660"

    html =
      lv
      |> element(~s{button[phx-value-entry_ref="#{ctx.entry.entry_ref}"]})
      |> render_click()

    refute html =~ "41,660"
    assert Owners.timeline(ctx.scope, ctx.vehicle) == []
  end

  test "a visitor is offered no such control", ctx do
    {:ok, _lv, html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

    assert html =~ "41,660"
    refute html =~ "phx-value-entry_ref"
  end

  test "santo's own decode entries carry no control for anyone", ctx do
    conn = log_in_user(build_conn(), ctx.user)
    {:ok, _lv, html} = live(conn, ~p"/v/#{ctx.vehicle.public_id}")

    # The registry's own claims are not the owner's to remove — the line is the
    # asserting party, and santo is not them.
    controls = Regex.scan(~r/phx-value-entry_ref="([^"]+)"/, html)
    assert length(controls) == 1
  end
end
