defmodule SantoApiWeb.ComposerTest do
  @moduledoc """
  The entry composer (owner_surface §1) — the make-or-break surface.

  What these tests hold to: a fill-up is three numbers and a save, every mode
  reaches the ledger through the same self-ratification path, and a car the
  caller does not steward is not writable.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)

    %{vehicle: vehicle, scope: Scope.for_user(ctx.user)}
  end

  describe "access" do
    test "anonymous visitors are sent to log in", ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/log")
    end

    test "a signed-in stranger is turned away from a car they do not steward", ctx do
      conn = log_in_user(build_conn(), SantoApi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: to, flash: %{"error" => error}}}} =
               live(conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      assert to == "/v/#{ctx.vehicle.public_id}"
      assert error =~ "maintain"
    end

    test "an unknown car is a 404, not a blank composer", ctx do
      assert_raise SantoApiWeb.VehicleNotFound, fn ->
        live(ctx.conn, ~p"/v/nosuchcar/log")
      end
    end
  end

  describe "the fill-up — the ten-second bar" do
    test "opens already on Fill-up, with today's date", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      assert has_element?(view, "#composer-form")
      assert has_element?(view, "[data-mode=fuel][aria-current=true]")
      assert has_element?(view, "#entry_odometer")
      assert has_element?(view, "#entry_volume")
      assert has_element?(view, "#entry_price")

      assert view
             |> element("#entry_date")
             |> render() =~ Date.to_iso8601(Date.utc_today())
    end

    test "three numbers and a save lands the entry on the car's page", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#composer-form",
                 entry: %{odometer: "41660", volume: "13.1", price: "67.45"}
               )
               |> render_submit()

      # Straight back to the car, because the payoff is seeing the page get richer.
      assert to == "/v/#{ctx.vehicle.public_id}"

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert entry.party == ctx.user.handle
      assert entry.date == Date.utc_today()

      by_predicate = Map.new(entry.claims, &{&1.predicate, &1.value})
      assert by_predicate["observation.mileage"] == 41_660
      assert by_predicate["event.fuel"]["volume"] == "13.1"
      assert by_predicate["event.fuel"]["unit"] == "gal"
      assert by_predicate["event.fuel"]["total_cents"] == 6745
      assert by_predicate["event.fuel"]["currency"] == "USD"
    end

    test "money is exact — dollars in, integer cents stored", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view
      |> form("#composer-form", entry: %{odometer: "41660", volume: "13.1", price: "0.10"})
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      fuel = Enum.find(entry.claims, &(&1.predicate == "event.fuel"))
      assert fuel.value["total_cents"] == 10
    end

    test "a price is optional — volume and odometer are the entry", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view
      |> form("#composer-form", entry: %{odometer: "41660", volume: "13.1", price: ""})
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      fuel = Enum.find(entry.claims, &(&1.predicate == "event.fuel"))
      assert fuel.value["total_cents"] == nil
    end

    test "the odometer starts from the last reading, so the next one is two numbers", ctx do
      {:ok, _entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-01],
          claims: [%{predicate: "observation.mileage", value: 41_660}]
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")
      assert view |> element("#entry_odometer") |> render() =~ "41660"
    end

    test "a fill-up with no volume says so instead of writing half an entry", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      html =
        view
        |> form("#composer-form", entry: %{odometer: "41660", volume: "", price: ""})
        |> render_submit()

      assert html =~ "how much fuel"
      assert Registry.timeline(ctx.vehicle.id) == []
    end
  end

  describe "service, mod and note" do
    test "service records what was done and who did it", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=service]") |> render_click()

      view
      |> form("#composer-form",
        entry: %{summary: "Oil and filter", performer: "Bruce Canepa", odometer: "41700"}
      )
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      by_predicate = Map.new(entry.claims, &{&1.predicate, &1.value})
      assert by_predicate["event.service"]["summary"] == "Oil and filter"
      assert by_predicate["event.service"]["performer"] == "Bruce Canepa"
      assert by_predicate["observation.mileage"] == 41_700
    end

    test "a mod is a summary, and its trait delta moves current state", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=modification]") |> render_click()

      view
      |> form("#composer-form",
        entry: %{
          summary: "Wrapped it Signal Green",
          area: "exterior",
          trait: "state.exterior",
          trait_summary: "Signal Green wrap over Slate Grey"
        }
      )
      |> render_submit()

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      trait = vehicle.current_state["state.exterior"]
      assert trait["value"]["summary"] == "Signal Green wrap over Slate Grey"
      assert trait["source"] == "event"
    end

    test "a mod without a trait delta is timeline-only", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=modification]") |> render_click()

      view
      |> form("#composer-form", entry: %{summary: "New shift knob", trait: ""})
      |> render_submit()

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state == %{}
      assert [_entry] = Registry.timeline(ctx.vehicle.id)
    end

    test "a note takes anything and is never rejected for shape", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=note]") |> render_click()

      view
      |> form("#composer-form", entry: %{text: "Sounds different cold. Watch it."})
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert [claim] = entry.claims
      assert claim.predicate == "event.note"
      assert claim.value["text"] == "Sounds different cold. Watch it."
    end

    test "a plan is dated intent and never changes current state", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=plan]") |> render_click()

      view
      |> form("#composer-form",
        entry: %{text: "Try a lighter set of wheels next season", area: "Wheels & tires"}
      )
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert [claim] = entry.claims
      assert claim.predicate == "event.plan"
      assert claim.value["area"] == "Wheels & tires"

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state == %{}

      {:ok, page, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
      assert has_element?(page, "[data-plan=true]", "Planned:")
    end

    test "an empty note says so rather than logging nothing", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=note]") |> render_click()
      html = view |> form("#composer-form", entry: %{text: "   "}) |> render_submit()

      assert html =~ "Nothing to log"
      assert Registry.timeline(ctx.vehicle.id) == []
    end
  end

  describe "photo-first updates" do
    test "a photo can be the update, with preview and public car-page delivery", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log?mode=note")

      assert has_element?(view, "[data-mode=note][aria-current=true]")

      upload =
        file_input(view, "#composer-form", :photos, [
          %{
            name: "cayman-paddock.jpg",
            content: File.read!("priv/demo/media/cayman-autocross-paddock.jpg"),
            type: "image/jpeg"
          }
        ])

      assert render_upload(upload, "cayman-paddock.jpg") =~ "cayman-paddock.jpg"
      assert has_element?(view, "[id^=composer-photo-] img")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#composer-form", entry: %{text: "", date: "2026-08-10"})
               |> render_submit()

      assert to == "/v/#{ctx.vehicle.public_id}"
      assert [%{claims: [], photos: [_photo]}] = Owners.timeline(nil, ctx.vehicle)

      {:ok, page, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
      assert has_element?(page, "#vehicle-hero-photo[srcset]")
      assert has_element?(page, "#vehicle-gallery [id^=vehicle-photo-]")
      assert has_element?(page, "#vehicle-logbook [id*=-photo-]")
    end
  end

  describe "date and visibility" do
    test "back-filling is one field, because it is a first-session behavior", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=note]") |> render_click()

      view
      |> form("#composer-form",
        entry: %{text: "Timing belt, per the old receipt", date: "2019-04-12"}
      )
      |> render_submit()

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert entry.date == ~D[2019-04-12]
    end

    test "one toggle keeps an entry off the public page", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/log")

      view |> element("[data-mode=note]") |> render_click()

      view
      |> form("#composer-form",
        entry: %{text: "Where the spare key lives", visibility: "private"}
      )
      |> render_submit()

      assert Registry.timeline(ctx.vehicle.id) == []
    end
  end

  describe "the spec panel — §2b cold start" do
    test "shows the seed traits as fields", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/spec")

      for trait <- SantoApi.Registry.Vocabulary.trait_predicates() do
        assert has_element?(view, "#spec_#{String.replace(trait, ".", "_")}")
      end
    end

    test "saving a baseline writes one observed claim per filled field", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/spec")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#spec-form",
                 spec: %{
                   "state.engine" => "3.4 flat-six, stock",
                   "state.wheels_tires" => "19x8 / 19x9.5 Carrera S",
                   "state.transmission" => "",
                   "state.suspension" => "",
                   "state.brakes" => "",
                   "state.exterior" => ""
                 }
               )
               |> render_submit()

      assert to == "/v/#{ctx.vehicle.public_id}"

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state["state.engine"]["value"]["summary"] == "3.4 flat-six, stock"
      assert vehicle.current_state["state.wheels_tires"]["value"]["summary"] =~ "Carrera S"
      refute Map.has_key?(vehicle.current_state, "state.brakes")
    end

    test "an all-empty spec writes nothing", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/spec")

      html =
        view
        |> form("#spec-form", spec: Map.new(trait_keys(), &{&1, ""}))
        |> render_submit()

      assert html =~ "Nothing to save"
      assert Registry.list_claims(ctx.vehicle.id) |> Enum.all?(&(&1.method == :santo))
    end

    test "a stranger cannot reach it", ctx do
      conn = log_in_user(build_conn(), SantoApi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: _to, flash: %{"error" => _error}}}} =
               live(conn, ~p"/v/#{ctx.vehicle.public_id}/spec")
    end
  end

  describe "the car page" do
    test "names its steward and offers the composer to them", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ ctx.user.handle
      assert html =~ "Maintained by"
      assert html =~ "/log"
    end

    test "says maintained by, never owned by", ctx do
      {:ok, _view, html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "Maintained by"
      refute html =~ "Owned by"
    end

    test "offers a visitor no composer", ctx do
      {:ok, view, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      refute has_element?(view, "a[href='/v/#{ctx.vehicle.public_id}/log']")
    end

    test "lights the owner's own entries and leaves the registry's grey", ctx do
      # A registry-sourced event, hand-entered at the bench: same `method: :human`
      # as an owner entry, different asserting party. The party is what the tick
      # is about (§6) — attribution, not how the row was typed.
      {:ok, claim} =
        Registry.propose_claim(ctx.vehicle, %{
          "predicate" => "event.service",
          "value" => %{"summary" => "Annual service, per the invoice", "performer" => nil},
          "scope_date" => "2019-04-12"
        })

      {:ok, _ratified} = Registry.ratify_claim(claim.id)

      {:ok, _entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [%{predicate: "event.note", value: %{"text" => "My own line"}}]
        })

      {:ok, view, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      assert has_element?(view, "[data-owner=true]")
      assert has_element?(view, "[data-owner=false]")
    end
  end

  defp trait_keys, do: SantoApi.Registry.Vocabulary.trait_predicates()
end
