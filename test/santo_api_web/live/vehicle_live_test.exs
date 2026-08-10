defmodule SantoApiWeb.VehicleLiveTest do
  @moduledoc """
  The public car page. Its job is to say what the ledger supports and no more,
  so most of these tests are about what it refuses to say.
  """
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.FreeAcquisition
  alias SantoApi.FreeAcquisition.Cohort
  alias SantoApi.Registry
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo

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

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#vehicle-title", "2007 Porsche")

    assert has_element?(
             view,
             "#vehicle-identity",
             String.replace(vehicle.identity_key, "vin:", "")
           )
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

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#vehicle-spec", "2.7 flat-six, rebuilt")
  end

  test "a car nobody has described says so instead of inventing a description", %{conn: conn} do
    {:ok, vehicle} = Registry.register_chassis(:porsche, :pre_vin, "9113600123")

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#vehicle-description-gap", "Nobody has described this car yet")
    assert has_element?(view, "#record-empty", "Nothing on file yet")
  end

  test "an empty logbook invites an entry rather than showing a clean record", %{conn: conn} do
    vehicle = car()

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#logbook-empty", "No updates yet")
    refute has_element?(view, "#vehicle-logbook", "clean")
  end

  test "admitted entries appear on the timeline; proposed ones do not", %{conn: conn} do
    vehicle = car()

    admitted =
      admit(vehicle, %{
        predicate: "event.service",
        value: %{
          "summary" => "Annual service and IMS inspection",
          "performer" => "Flat 6 Motors"
        },
        scope_date: ~D[2025-06-01]
      })

    {:ok, proposed} =
      Registry.propose_claim(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "this has not been confirmed"},
        scope_date: ~D[2025-07-01]
      })

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#entry-#{admitted.id}", "Annual service and IMS inspection")
    assert has_element?(view, "#entry-#{admitted.id}", "Flat 6 Motors")
    refute has_element?(view, "#entry-#{proposed.id}")
    refute has_element?(view, "#vehicle-record", "this has not been confirmed")
  end

  test "an entry says its details once — what happened leads, the reading follows", %{conn: conn} do
    vehicle = car()
    fill_up = Registry.new_entry_ref()

    admit(vehicle, %{
      predicate: "event.fuel",
      value: %{"volume" => "13.1", "unit" => "gal"},
      scope_date: ~D[2026-06-14],
      entry_ref: fill_up
    })

    admit(vehicle, %{
      predicate: "observation.mileage",
      value: 74_310,
      scope_date: ~D[2026-06-14],
      entry_ref: fill_up
    })

    {:ok, live, _html} = live(conn, ~p"/v/#{vehicle.public_id}")
    entry = live |> element("li.vs-tick", "13.1 gal") |> render()

    # The fill-up is what happened; the odometer is a detail of it.
    assert entry =~ "13.1 gal of fuel"
    assert entry =~ "74,310 mi"
  end

  test "an odometer entry on its own does not print its reading twice", %{conn: conn} do
    vehicle = car()

    admit(vehicle, %{
      predicate: "observation.mileage",
      value: 74_310,
      scope_date: ~D[2026-06-14]
    })

    {:ok, live, _html} = live(conn, ~p"/v/#{vehicle.public_id}")
    entry = live |> element("li.vs-tick", "74,310") |> render()

    assert entry =~ "74,310 miles"
    assert length(String.split(entry, "74,310")) - 1 == 1
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

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    refute has_element?(view, "#entry-#{claim.id}")
    assert Enum.any?(Registry.list_claims(vehicle.id), &(&1.id == claim.id))
  end

  test "the steward sees their own private entry, marked private", %{conn: conn} do
    vehicle = car()
    user = SantoApi.AccountsFixtures.user_fixture(%{handle: "mhyrr"})
    {:ok, _stewardship} = SantoApi.Owners.grant_stewardship(user, vehicle)

    claim =
      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "kept in the second garage"},
        scope_date: ~D[2025-06-01]
      })

    {:ok, _hidden} = Registry.set_visibility(claim, :private)

    {:ok, view, _html} = live(log_in_user(conn, user), ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#entry-#{claim.id}", "kept in the second garage")
    assert has_element?(view, "#entry-#{claim.id}", "Not on the public page")
  end

  test "a conflicted fact says sources disagree instead of picking quietly", %{conn: conn} do
    vehicle = car()
    other_source = Registry.ensure_party("Kardex copy", :registry)
    santo = Enum.find(Registry.list_claims(vehicle.id), &(&1.predicate == "build.plant"))

    # Santo already claims the plant from the VIN. A second party naming it
    # differently is what a conflict actually is — one party disagreeing with
    # itself is just a duplicate.
    {:ok, claim} =
      Registry.propose_claim(vehicle, other_source, %{
        predicate: "build.plant",
        value: "Osnabrück"
      })

    {:ok, _admitted} = Registry.ratify_claim(claim.id)

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#fact-build-plant[data-status='conflicted']", "sources disagree")
    assert has_element?(view, "#claim-#{santo.id}-party", "Vin Santo")
    assert has_element?(view, "#claim-#{claim.id}-party", "Kardex copy")
    assert has_element?(view, "#claim-#{claim.id}-value", "Osnabrück")
    assert selector_count(view, "#fact-build-plant-claims article[data-claim-state]") == 2
  end

  test "a proposed factory fact shows its party, state, date, artifact, and public source", %{
    conn: conn
  } do
    {:ok, vehicle} = Registry.register_chassis(:ferrari, :pre_vin, "04269")
    party = Registry.ensure_party("RM Auctions", :vendor)
    url = "https://example.com/auction/04269"

    {:ok, artifact} =
      Registry.create_reference_artifact(vehicle, party, %{
        source_url: url,
        acquired_at: ~U[2026-08-04 12:00:00.000000Z],
        metadata: %{"rights_profile" => "public-pointer-only-v1"}
      })

    {:ok, claim} =
      Registry.propose_claim(vehicle, party, %{
        predicate: "build.production_date",
        value: "1972-10-18",
        scope_date: ~D[1972-10-18],
        artifact_id: artifact.id
      })

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#vehicle-record")

    assert has_element?(
             view,
             "#fact-build-production_date[data-status='unverified']",
             "unconfirmed"
           )

    assert has_element?(view, "#fact-build-production_date-disclosure", "18 October 1972")
    assert has_element?(view, "#claim-#{claim.id}[data-claim-state='proposed']")
    assert has_element?(view, "#claim-#{claim.id}-party", "RM Auctions")
    assert has_element?(view, "#claim-#{claim.id}-applicable", "18 October 1972")
    assert has_element?(view, "#claim-#{claim.id}-artifact", "Reference")
    assert has_element?(view, "#claim-#{claim.id}-artifact", "acquired 4 August 2026")

    assert has_element?(
             view,
             ~s(#fact-build-production_date-claims a[id^="fact-build-production_date-source-"][href="#{url}"])
           )
  end

  test "private artifact evidence leaves the fact visible and its URL undisclosed", %{conn: conn} do
    {:ok, vehicle} = Registry.register_chassis(:ferrari, :pre_vin, "04270")
    party = Registry.ensure_party("Private archive", :registry)
    url = "https://private.example/04270-build-sheet"

    {:ok, artifact} =
      Registry.create_reference_artifact(vehicle, party, %{
        source_url: url,
        metadata: %{"rights_profile" => "owner-private-v1"}
      })

    {:ok, artifact} = Registry.set_visibility(artifact, :private)

    {:ok, claim} =
      Registry.propose_claim(vehicle, party, %{
        predicate: "identity.model_year",
        value: 1972,
        artifact_id: artifact.id
      })

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "#fact-identity-model_year", "1972")
    assert has_element?(view, "#claim-#{claim.id}-artifact", "No public artifact")
    refute has_element?(view, ~s(a[href="#{url}"]))
  end

  test "duplicate evidence URLs render once without collapsing their claims", %{conn: conn} do
    {:ok, vehicle} = Registry.register_chassis(:ferrari, :pre_vin, "04271")
    rm = Registry.ensure_party("RM Auctions", :vendor)
    bat = Registry.ensure_party("Bring a Trailer", :vendor)
    url = "https://example.com/shared-dino-record"

    {:ok, rm_artifact} =
      Registry.create_reference_artifact(vehicle, rm, %{
        source_url: url,
        metadata: %{"rights_profile" => "public-pointer-only-v1"}
      })

    {:ok, bat_artifact} =
      Registry.create_reference_artifact(vehicle, bat, %{
        source_url: url,
        metadata: %{"rights_profile" => "public-pointer-only-v1"}
      })

    value = %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"}

    for {party, artifact} <- [{rm, rm_artifact}, {bat, bat_artifact}] do
      assert {:ok, _claim} =
               Registry.propose_claim(
                 vehicle,
                 party,
                 %{predicate: "identity.model", value: value, artifact_id: artifact.id},
                 distinct_by_artifact: true
               )
    end

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert selector_count(view, "#fact-identity-model-claims article[data-claim-state]") == 2
    assert selector_count(view, ~s(#fact-identity-model-claims a[href="#{url}"])) == 1
    assert has_element?(view, "#fact-identity-model-claims", "RM Auctions")
    assert has_element?(view, "#fact-identity-model-claims", "Bring a Trailer")
  end

  test "the record counts facts honestly, without a percentage of nothing", %{conn: conn} do
    {:ok, bare} = Registry.register_chassis(:porsche, :pre_vin, "9113600124")

    {:ok, view, _html} = live(conn, ~p"/v/#{bare.public_id}")

    refute has_element?(view, "#record-strength")
  end

  test "the ratified 04268 corpus record shows identity, sales, attribution, and evidence", %{
    conn: conn
  } do
    entry =
      Cohort.load!()["entries"]
      |> Enum.find(&(&1["id"] == "ferrari-1972-dino-04268"))

    assert %{sales_ratified: 2, failures: []} =
             FreeAcquisition.run([entry], acquire: false, ratify: true)

    vehicle = Repo.get_by!(Vehicle, identity_key: "chassis:ferrari:pre_vin:04268")

    {:ok, _proposed} =
      Registry.propose_claim(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "Proposed events remain private to the ledger"},
        scope_date: ~D[2025-01-01]
      })

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(view, "h1", "1972 Ferrari Dino 246 GTS")

    for fact <- ["identity-marque", "identity-model", "identity-model_year"] do
      assert has_element?(view, "#fact-#{fact}[data-status='unverified']", "unconfirmed")
    end

    assert selector_count(view, "#fact-identity-model-claims article[data-claim-state]") == 2
    assert has_element?(view, "#fact-identity-model-claims", "RM Auctions")
    assert has_element?(view, "#fact-identity-model-claims", "Bring a Trailer")

    assert has_element?(
             view,
             ~s(#fact-identity-model-claims a[href="https://rmsothebys.com/auctions/az14/lots/r187-1972-ferrari-dino-246-gts/"])
           )

    assert has_element?(
             view,
             ~s(#fact-identity-model-claims a[href="https://bringatrailer.com/listing/1972-ferrari-dino-246-gts-3/"])
           )

    assert has_element?(
             view,
             "#vehicle-logbook li.vs-tick",
             "Sold at RM Auctions for $352,000"
           )

    assert has_element?(
             view,
             "#vehicle-logbook li.vs-tick",
             "Sold at Bring a Trailer for $630,000"
           )

    assert has_element?(view, "#vehicle-logbook li.vs-tick", "17 January 2014")
    assert has_element?(view, "#vehicle-logbook li.vs-tick", "27 July 2023")
    assert has_element?(view, "#vehicle-logbook li.vs-tick", "Recorded by RM Auctions")
    assert has_element?(view, "#vehicle-logbook li.vs-tick", "Recorded by Bring a Trailer")

    assert has_element?(
             view,
             ~s(#vehicle-logbook a[href="https://rmsothebys.com/auctions/az14/lots/r187-1972-ferrari-dino-246-gts/"])
           )

    assert has_element?(
             view,
             ~s(#vehicle-logbook a[href="https://bringatrailer.com/listing/1972-ferrari-dino-246-gts-3/"])
           )

    refute has_element?(view, "#vehicle-logbook li.vs-tick", "Proposed events remain private")
    refute has_element?(view, "#vehicle-record", "Proposed events remain private")
  end

  test "page query count stays flat as fact claims grow", %{conn: conn} do
    {:ok, small} = Registry.register_chassis(:ferrari, :pre_vin, "query-small")
    {:ok, large} = Registry.register_chassis(:ferrari, :pre_vin, "query-large")
    value = %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"}

    for {vehicle, count} <- [{small, 1}, {large, 30}], index <- 1..count do
      party = Registry.ensure_party("Query source #{vehicle.public_id} #{index}", :vendor)

      {:ok, artifact} =
        Registry.create_reference_artifact(vehicle, party, %{
          source_url: "https://example.com/#{vehicle.public_id}/#{index}",
          metadata: %{"rights_profile" => "public-pointer-only-v1"}
        })

      assert {:ok, _claim} =
               Registry.propose_claim(
                 vehicle,
                 party,
                 %{predicate: "identity.model", value: value, artifact_id: artifact.id},
                 distinct_by_artifact: true
               )
    end

    small_queries = page_query_count(conn, small)
    large_queries = page_query_count(build_conn(), large)

    assert large_queries == small_queries
    # The mutable story and generic event association each add one constant
    # page query; claim volume must still add none.
    assert large_queries <= 18
  end

  test "an admitted unsuccessful auction event renders as a high bid, not a sale", %{conn: conn} do
    vehicle = car()

    admit(vehicle, %{
      predicate: "event.sale",
      value: %{
        "venue" => "Mecum Auctions",
        "price" => 55_000,
        "currency" => "USD",
        "outcome" => "not_sold"
      },
      scope_date: ~D[2015-08-14]
    })

    {:ok, view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")

    assert has_element?(
             view,
             "#vehicle-logbook li.vs-tick",
             "High bid of $55,000 at Mecum Auctions; not sold"
           )

    refute has_element?(view, "#vehicle-logbook li.vs-tick", "Sold at Mecum Auctions")
  end

  defp selector_count(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.count()
  end

  defp page_query_count(conn, vehicle) do
    ref = make_ref()
    test_pid = self()
    handler_id = {__MODULE__, ref}

    :ok =
      :telemetry.attach(
        handler_id,
        [:santo_api, :repo, :query],
        fn _event, _measurements, _metadata, _config -> send(test_pid, {ref, :query}) end,
        nil
      )

    try do
      assert {:ok, _view, _html} = live(conn, ~p"/v/#{vehicle.public_id}")
      drain_queries(ref, 0)
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(ref, count) do
    receive do
      {^ref, :query} -> drain_queries(ref, count + 1)
    after
      0 -> count
    end
  end
end
