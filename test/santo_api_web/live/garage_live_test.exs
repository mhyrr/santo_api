defmodule SantoApiWeb.GarageLiveTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.EntryExtraction
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)
    %{vehicle: vehicle}
  end

  defp stub_entry(fields) do
    Req.Test.stub(EntryExtraction, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(fields)}]
      })
    end)
  end

  defp fuel_fields do
    %{
      "mode" => "fuel",
      "date" => "2026-08-09",
      "odometer" => 41_660,
      "volume" => "13.1",
      "unit" => "gal",
      "total_price" => "67.45",
      "unit_price" => nil,
      "currency" => "USD",
      "summary" => nil,
      "performer" => nil,
      "area" => nil,
      "outing_kind" => nil,
      "venue" => nil,
      "result" => nil,
      "note" => nil
    }
  end

  test "adding data is the first signed-in task and voice feeds the same box", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/garage")

    assert has_element?(view, "#garage-intake-form")
    assert has_element?(view, "#garage-dictation[phx-update='ignore']")
    assert has_element?(view, "#garage-voice-button[aria-label='Dictate update']")
    assert has_element?(view, ".club-intake-car-context", "2007 Porsche")
    assert has_element?(view, "#garage-cars a[href='/v/#{ctx.vehicle.public_id}']")
    assert has_element?(view, "#app-topbar a[href='/garage']", "Garage")
    assert has_element?(view, "#app-topbar form[action='/cars']")
  end

  test "a sentence becomes an editable read-back, then one reviewed update", ctx do
    stub_entry(fuel_fields())
    {:ok, view, _html} = live(ctx.conn, ~p"/garage")

    html =
      view
      |> form("#garage-intake-form",
        intake: %{
          vehicle: ctx.vehicle.public_id,
          text: "Filled it: 13.1 gallons for $67.45, 41,660 miles.",
          input_method: "text"
        }
      )
      |> render_submit()

    assert html =~ "Does this look right?"
    assert has_element?(view, "#review_volume[value='13.1']")
    assert has_element?(view, "#review_odometer[value='41660']")
    assert has_element?(view, "#review_price[value='67.45']")
    assert has_element?(view, "#review_currency[value='USD']")
    assert Registry.timeline(ctx.vehicle.id) == []

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#garage-review-form",
               review: %{
                 mode: "fuel",
                 date: "2026-08-09",
                 odometer: "41661",
                 volume: "13.1",
                 unit: "gal",
                 price: "67.45",
                 currency: "USD",
                 private: "false"
               }
             )
             |> render_submit()

    assert to =~ "/v/#{ctx.vehicle.public_id}/updates/"
    assert [entry] = Registry.timeline(ctx.vehicle.id)
    assert entry.method == :llm_extract
    by_predicate = Map.new(entry.claims, &{&1.predicate, &1.value})
    assert by_predicate["observation.mileage"] == 41_661
  end

  test "parser failure keeps every word as an ordinary editable note", ctx do
    Req.Test.stub(EntryExtraction, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)
    {:ok, view, _html} = live(ctx.conn, ~p"/garage")
    sentence = "Rattle behind the dash, but only on cold starts."

    view
    |> form("#garage-intake-form",
      intake: %{vehicle: ctx.vehicle.public_id, text: sentence, input_method: "text"}
    )
    |> render_submit()

    assert has_element?(view, "#garage-parse-notice", "every word")
    assert view |> element("#review_text") |> render() =~ sentence

    view
    |> form("#garage-review-form",
      review: %{mode: "note", date: "2026-08-09", text: sentence, private: "false"}
    )
    |> render_submit()

    assert [entry] = Registry.timeline(ctx.vehicle.id)
    assert entry.method == :human
    assert Enum.find(entry.claims, &(&1.predicate == "event.note")).value["text"] == sentence
  end

  test "a forged car selection never reaches extraction", ctx do
    {:ok, stranger_car} = Registry.register_chassis(:porsche, :pre_vin, "NOT-YOURS")
    {:ok, view, _html} = live(ctx.conn, ~p"/garage")

    html =
      render_hook(view, "parse_update", %{
        "intake" => %{
          "vehicle" => stranger_car.public_id,
          "text" => "Changed the oil",
          "input_method" => "text"
        }
      })

    assert html =~ "Choose one of your cars"
    assert Registry.timeline(stranger_car.id) == []
  end

  test "an empty garage makes adding the first car the only intake action", %{conn: conn} do
    user = SantoApi.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, user)
    assert Owners.list_stewarded_vehicles(Scope.for_user(user)) == []

    {:ok, view, _html} = live(conn, ~p"/garage")
    refute has_element?(view, "#garage-intake-form")
    assert has_element?(view, "#garage-empty-intake a[href='/start']")
  end
end
