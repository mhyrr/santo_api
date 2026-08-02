defmodule SantoApiWeb.VehicleIndexTest do
  @moduledoc """
  The registry index — every car we hold, and a way into each one.
  """
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Registry

  test "lists every car with a link to its page", %{conn: conn} do
    {:ok, cayman} = Registry.ingest("WP0AB29827U782968")
    {:ok, gt3} = Registry.ingest("WP0AC2A97JS176473")

    {:ok, live, html} = live(conn, ~p"/")

    # Titles are only as good as the decode. Santo mis-reads this Cayman VIN as
    # a Boxster (a known ../santo bug) and names no model at all for the GT3 —
    # both cars only read correctly on their corpus pages, where a ratified
    # vPIC claim supplies the model.
    assert html =~ "2007 Porsche Boxster"
    assert html =~ "2018 Porsche"

    assert live |> element(~s|a[href="/v/#{cayman.public_id}"]|) |> has_element?()
    assert live |> element(~s|a[href="/v/#{gt3.public_id}"]|) |> has_element?()
  end

  test "a car with nothing on it is still listed — the index hides nothing", %{conn: conn} do
    {:ok, bare} = Registry.register_chassis(:ferrari, :pre_vin, "01438")

    {:ok, live, _html} = live(conn, ~p"/")

    assert live |> element(~s|a[href="/v/#{bare.public_id}"]|) |> has_element?()
  end

  test "shows how much each car has on it, so a thin record reads as thin", %{conn: conn} do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")

    {:ok, claim} =
      Registry.propose_claim(vehicle, %{
        predicate: "event.service",
        value: %{"summary" => "Annual service", "performer" => "Flat 6 Motors"},
        scope_date: ~D[2025-06-01]
      })

    {:ok, _admitted} = Registry.ratify_claim(claim.id)

    {:ok, live, _html} = live(conn, ~p"/")

    row = live |> element(~s|a[href="/v/#{vehicle.public_id}"]|) |> render()

    assert row =~ "1 entry"
    assert row =~ "facts"
  end

  test "an empty registry says so rather than showing a blank page", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ "No cars in the registry yet"
  end

  test "the index carries no account chrome — it is a public surface", %{conn: conn} do
    {:ok, _live, html} = live(conn, ~p"/")

    refute html =~ "phoenixframework.org"
    refute html =~ "Get Started"
  end
end
