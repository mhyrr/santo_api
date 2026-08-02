defmodule SantoApiWeb.VehicleLiveTest do
  @moduledoc """
  The public car page. Its job is to say what the ledger supports and no more,
  so most of these tests are about what it refuses to say.
  """
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Registry

  @cayman "WP0AB29827U782968"

  defp admit(vehicle, attrs) do
    {:ok, claim} = Registry.propose_claim(vehicle, attrs)
    {:ok, admitted} = Registry.ratify_claim(claim.id)
    admitted
  end

  defp car do
    {:ok, vehicle} = Registry.ingest(@cayman)
    vehicle
  end

  test "reaches the page by public handle, with no account", %{conn: conn} do
    vehicle = car()

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "2007 Porsche"
    assert html =~ vehicle.identity_key |> String.replace("vin:", "")
  end

  test "a VIN redirects to the canonical handle rather than serving a second URL", %{conn: conn} do
    vehicle = car()

    conn = get(conn, ~p"/vin/#{@cayman}")

    assert redirected_to(conn) == "/v/#{vehicle.public_id}"
  end

  test "an unknown car is a 404, not a crash", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/vin/WP0ZZZ99ZTS392124") end
    assert_error_sent 404, fn -> get(conn, ~p"/v/aaaaaaaaaa") end
  end

  test "the spec line comes from current state, not the decode", %{conn: conn} do
    vehicle = car()

    admit(vehicle, %{
      predicate: "state.engine",
      value: %{"summary" => "2.7 flat-six, rebuilt"},
      scope_date: ~D[2025-02-02]
    })

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "2.7 flat-six, rebuilt"
  end

  test "a car nobody has described says so instead of inventing a description", %{conn: conn} do
    {:ok, vehicle} = Registry.register_chassis(:porsche, :pre_vin, "9113600123")

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "Nobody has described this car yet"
    assert html =~ "Nothing on file yet"
  end

  test "an empty logbook invites an entry rather than showing a clean record", %{conn: conn} do
    vehicle = car()

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "No entries yet"
    refute html =~ "clean"
  end

  test "admitted entries appear on the timeline; proposed ones do not", %{conn: conn} do
    vehicle = car()

    admit(vehicle, %{
      predicate: "event.service",
      value: %{"summary" => "Annual service and IMS inspection", "performer" => "Flat 6 Motors"},
      scope_date: ~D[2025-06-01]
    })

    {:ok, _proposed} =
      Registry.propose_claim(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "this has not been confirmed"},
        scope_date: ~D[2025-07-01]
      })

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "Annual service and IMS inspection"
    assert html =~ "Flat 6 Motors"
    refute html =~ "this has not been confirmed"
  end

  test "a private entry is off the page but still in the ledger", %{conn: conn} do
    vehicle = car()

    claim =
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "kept in the second garage"},
        scope_date: ~D[2025-06-01]
      })

    {:ok, _hidden} = Registry.set_visibility(claim, :private)

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    refute html =~ "kept in the second garage"
    assert Enum.any?(Registry.list_claims(vehicle.id), &(&1.id == claim.id))
  end

  test "a conflicted fact says sources disagree instead of picking quietly", %{conn: conn} do
    vehicle = car()
    other_source = Registry.ensure_party("Kardex copy", :registry)

    # Santo already claims the plant from the VIN. A second party naming it
    # differently is what a conflict actually is — one party disagreeing with
    # itself is just a duplicate.
    {:ok, claim} =
      Registry.propose_claim(vehicle, other_source, %{
        predicate: "build.plant",
        value: "Osnabrück"
      })

    {:ok, _admitted} = Registry.ratify_claim(claim.id)

    {:ok, _live, html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert html =~ "sources disagree"
  end

  test "the record counts facts honestly, without a percentage of nothing", %{conn: conn} do
    {:ok, bare} = Registry.register_chassis(:porsche, :pre_vin, "9113600124")

    {:ok, _live, html} = live(conn, ~p"/v/#{bare.public_id}")

    refute html =~ "facts on this car are backed"
  end
end
