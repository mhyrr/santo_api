defmodule SantoApi.Registry.VocabularyTest do
  use ExUnit.Case, async: true

  alias SantoApi.Registry.Vocabulary

  describe "validate/2" do
    test "accepts every v1 predicate with a well-formed value" do
      assert :ok = Vocabulary.validate("identity.marque", "porsche")
      assert :ok = Vocabulary.validate("identity.model", %{"code" => "959", "label" => "959"})
      assert :ok = Vocabulary.validate("identity.model", %{"code" => "959", "label" => nil})
      assert :ok = Vocabulary.validate("identity.model_year", 1988)
      assert :ok = Vocabulary.validate("identity.market", "row")
      assert :ok = Vocabulary.validate("identity.market", "us")
      assert :ok = Vocabulary.validate("build.plant", "Stuttgart-Zuffenhausen")
      assert :ok = Vocabulary.validate("build.variant", "sport")
    end

    test "rejects malformed values" do
      assert {:error, _} = Vocabulary.validate("identity.model_year", "1988")
      assert {:error, _} = Vocabulary.validate("identity.market", "unknown")
      assert {:error, _} = Vocabulary.validate("identity.marque", :porsche)
      assert {:error, _} = Vocabulary.validate("identity.model", %{"code" => nil, "label" => "x"})
      assert {:error, _} = Vocabulary.validate("observation.mileage", -1)
      assert {:error, _} = Vocabulary.validate("observation.mileage", "43210")
    end

    test "the vocabulary is closed: unknown predicates are rejected" do
      assert {:error, :unknown_predicate} = Vocabulary.validate("legal.lien_holder", "a bank")
    end

    test "paint code carries code and/or label — documents differ on which they state" do
      # CoA states "Slate Grey Metallic/59"; the window sticker states only the label.
      assert :ok =
               Vocabulary.validate("build.paint_code", %{
                 "code" => "59",
                 "label" => "Slate Grey Metallic"
               })

      assert :ok = Vocabulary.validate("build.paint_code", %{"code" => "226", "label" => nil})

      assert :ok =
               Vocabulary.validate("build.paint_code", %{
                 "code" => nil,
                 "label" => "Fayence Yellow"
               })

      assert {:error, _} =
               Vocabulary.validate("build.paint_code", %{"code" => nil, "label" => nil})

      assert {:error, _} = Vocabulary.validate("build.paint_code", "L041")
    end

    test "production and delivery dates are ISO dates" do
      assert :ok = Vocabulary.validate("build.production_date", "2007-03-26")
      assert :ok = Vocabulary.validate("provenance.delivery_date", "2005-04-29")
      assert {:error, _} = Vocabulary.validate("build.production_date", "3/26/2007")
      assert {:error, _} = Vocabulary.validate("provenance.delivery_date", "29APR05")
    end

    test "delivery dealer names the dealer, location optional" do
      assert :ok =
               Vocabulary.validate("provenance.delivery_dealer", %{
                 "name" => "Braman Motorcars",
                 "location" => "West Palm Beach, FL"
               })

      assert :ok =
               Vocabulary.validate("provenance.delivery_dealer", %{
                 "name" => "Sonnen Porsche",
                 "location" => nil
               })

      assert {:error, _} =
               Vocabulary.validate("provenance.delivery_dealer", %{
                 "name" => nil,
                 "location" => "x"
               })
    end

    test "sale events carry venue and price" do
      assert :ok =
               Vocabulary.validate("event.sale", %{
                 "venue" => "Bring a Trailer",
                 "price" => 33_000,
                 "currency" => "USD"
               })

      assert :ok =
               Vocabulary.validate("event.sale", %{
                 "venue" => "Mecum Auctions",
                 "price" => 55_000,
                 "currency" => "USD",
                 "outcome" => "not_sold"
               })

      assert {:error, _} =
               Vocabulary.validate("event.sale", %{
                 "venue" => "Mecum Auctions",
                 "price" => 55_000,
                 "currency" => "USD",
                 "outcome" => "pending"
               })

      assert {:error, _} =
               Vocabulary.validate("event.sale", %{
                 "venue" => "Bring a Trailer",
                 "price" => 65_000,
                 "currency" => "USD",
                 "outcome" => "sold"
               })

      assert {:error, _} =
               Vocabulary.validate("event.sale", %{
                 "venue" => nil,
                 "price" => 33_000,
                 "currency" => "USD"
               })

      assert {:error, _} =
               Vocabulary.validate("event.sale", %{
                 "venue" => "Bring a Trailer",
                 "price" => "33k",
                 "currency" => "USD"
               })

      assert Vocabulary.scope_kind("event.sale") == :event
    end

    test "service events carry a summary, performer optional" do
      assert :ok =
               Vocabulary.validate("event.service", %{
                 "summary" => "Suspension recall campaign; new tires",
                 "performer" => "Porsche of Colorado Springs"
               })

      assert :ok =
               Vocabulary.validate("event.service", %{
                 "summary" => "Oil change",
                 "performer" => nil
               })

      assert {:error, _} =
               Vocabulary.validate("event.service", %{"summary" => nil, "performer" => "x"})
    end
  end

  describe "logbook predicates (TK-009)" do
    test "fill-ups carry volume and unit; money is integer cents, never floats" do
      assert :ok = Vocabulary.validate("event.fuel", %{"volume" => "13.1", "unit" => "gal"})

      assert :ok =
               Vocabulary.validate("event.fuel", %{
                 "volume" => "49.6",
                 "unit" => "l",
                 "total_cents" => 6_745,
                 "currency" => "USD",
                 "grade" => "93",
                 "station" => "Shell",
                 "partial" => false
               })

      assert {:error, _} = Vocabulary.validate("event.fuel", %{"volume" => 13.1, "unit" => "gal"})

      assert {:error, _} =
               Vocabulary.validate("event.fuel", %{"volume" => "13.1", "unit" => "liters"})

      assert {:error, _} =
               Vocabulary.validate("event.fuel", %{"volume" => "-2", "unit" => "gal"})

      assert {:error, _} =
               Vocabulary.validate("event.fuel", %{
                 "volume" => "13.1",
                 "unit" => "gal",
                 "total_cents" => 67.45
               })
    end

    test "a stated total becomes integer cents, whatever shape it arrived in" do
      # The measured quantities are what the ledger holds: gallons and the
      # amount paid. Both can be stored exactly; the price per gallon between
      # them is a quotient that usually cannot, so it is derived at read time
      # and never written.
      assert {%{"total_cents" => 6745}, %{}} =
               Vocabulary.normalize("event.fuel", %{
                 "volume" => "13.1",
                 "unit" => "gal",
                 "cost" => "67.45",
                 "currency" => "USD"
               })

      assert {%{"total_cents" => 6745}, %{}} =
               Vocabulary.normalize("event.fuel", %{
                 "volume" => "13.1",
                 "unit" => "gal",
                 "cost" => "$67.45"
               })

      # A JSON number from an assistant is rounded to the cent rather than
      # refused — the float never survives into the ledger either way.
      assert {%{"total_cents" => 6745}, %{}} =
               Vocabulary.normalize("event.fuel", %{
                 "volume" => "13.1",
                 "unit" => "gal",
                 "cost" => 67.45
               })
    end

    test "a stated price per gallon is multiplied out once, on the way in" do
      assert {%{"total_cents" => 6747}, %{}} =
               Vocabulary.normalize("event.fuel", %{
                 "volume" => "13.1",
                 "unit" => "gal",
                 "unit_price" => "5.15"
               })
    end

    test "an explicit total wins, and the values it beat are not thrown away" do
      {value, leftover} =
        Vocabulary.normalize("event.fuel", %{
          "volume" => "13.1",
          "unit" => "gal",
          "total_cents" => 6745,
          "cost" => "99.99"
        })

      assert value["total_cents"] == 6745
      refute Map.has_key?(value, "cost")
      # Somebody asserted 99.99. We are not storing it, so it is somebody's
      # words now — which is a thing to keep, not a thing to drop.
      assert leftover == %{"cost" => "99.99"}
    end

    test "a price nobody can read stays as the words it arrived in" do
      {value, leftover} =
        Vocabulary.normalize("event.fuel", %{
          "volume" => "13.1",
          "unit" => "gal",
          "cost" => "about sixty bucks"
        })

      # The fill-up is still a fill-up, and still valid without a price.
      assert :ok = Vocabulary.validate("event.fuel", value)
      refute Map.has_key?(value, "total_cents")
      assert leftover == %{"cost" => "about sixty bucks"}
    end

    test "a key the predicate has no room for is kept rather than swallowed" do
      {value, leftover} =
        Vocabulary.normalize("event.fuel", %{
          "volume" => "13.1",
          "unit" => "gal",
          "total_cents" => 6745,
          "pump" => 4,
          "paid_with" => "the blue card"
        })

      assert :ok = Vocabulary.validate("event.fuel", value)
      assert value["volume"] == "13.1"
      assert leftover == %{"pump" => 4, "paid_with" => "the blue card"}
    end

    test "every logbook predicate keeps its own optional keys" do
      for {predicate, value} <- [
            {"event.service", %{"summary" => "Oil and filter", "performer" => "Canepa"}},
            {"event.modification",
             %{"summary" => "Camber", "area" => "suspension", "detail" => "2.5 front"}},
            {"event.note", %{"text" => "Sounds different cold"}},
            {"event.outing",
             %{"kind" => "autocross", "venue" => "Crows", "result" => "2nd", "summary" => "Good"}},
            {"state.suspension", %{"summary" => "Bilstein", "code" => "B16", "detail" => "PSS10"}}
          ] do
        assert {^value, leftover} = Vocabulary.normalize(predicate, value)
        assert leftover == %{}, "#{predicate} lost keys it validates: #{inspect(leftover)}"
      end
    end

    test "a value that is not a map has nothing to lift out of it" do
      assert Vocabulary.normalize("observation.mileage", 41_660) == {41_660, %{}}
      assert Vocabulary.normalize("identity.marque", "porsche") == {"porsche", %{}}
    end

    test "modifications carry a summary; area stays a free string" do
      assert :ok = Vocabulary.validate("event.modification", %{"summary" => "LS1 swap"})

      assert :ok =
               Vocabulary.validate("event.modification", %{
                 "summary" => "Camber to 2.5 front",
                 "area" => "suspension",
                 "detail" => "Was 2.0; trying more front grip for autocross"
               })

      assert {:error, _} = Vocabulary.validate("event.modification", %{"summary" => nil})
      assert {:error, _} = Vocabulary.validate("event.modification", "LS1 swap")
    end

    test "notes are the escape hatch — any text is accepted" do
      assert :ok = Vocabulary.validate("event.note", %{"text" => "Car sat all winter."})
      assert {:error, _} = Vocabulary.validate("event.note", %{"text" => nil})
    end

    test "outings carry a kind from the closed list" do
      assert :ok =
               Vocabulary.validate("event.outing", %{
                 "kind" => "autocross",
                 "venue" => "Pikes Peak International Raceway",
                 "result" => "2nd in class",
                 "summary" => "Best run on the 32 psi setup"
               })

      assert :ok = Vocabulary.validate("event.outing", %{"kind" => "drive"})
      assert {:error, _} = Vocabulary.validate("event.outing", %{"kind" => "grocery-run"})
      assert {:error, _} = Vocabulary.validate("event.outing", %{"venue" => "somewhere"})
    end

    test "state traits carry a summary, code and detail optional (the Datsun case)" do
      assert :ok = Vocabulary.validate("state.engine", %{"summary" => "GM LS1 5.7L V8"})

      assert :ok =
               Vocabulary.validate("state.wheels_tires", %{
                 "summary" => "18x11 square, 315/30 Hoosier A7",
                 "code" => nil,
                 "detail" => "RB Wheels custom offset"
               })

      assert :ok = Vocabulary.validate("state.transmission", %{"summary" => "T-56 6-speed"})
      assert :ok = Vocabulary.validate("state.suspension", %{"summary" => "Techno Toy coilovers"})
      assert :ok = Vocabulary.validate("state.brakes", %{"summary" => "Wilwood 4-piston front"})
      assert :ok = Vocabulary.validate("state.exterior", %{"summary" => "Resprayed 905 red"})

      assert {:error, _} = Vocabulary.validate("state.engine", %{"summary" => nil})
      assert {:error, _} = Vocabulary.validate("state.engine", "LS1")

      assert {:error, :unknown_predicate} =
               Vocabulary.validate("state.exhaust", %{"summary" => "x"})
    end

    test "sets deltas validate against the trait vocabulary only (§2b)" do
      assert :ok =
               Vocabulary.validate("event.modification", %{
                 "summary" => "LS1 swap complete",
                 "sets" => [
                   %{"predicate" => "state.engine", "value" => %{"summary" => "GM LS1 5.7L V8"}},
                   %{"predicate" => "state.transmission", "value" => %{"summary" => "T-56"}}
                 ]
               })

      assert :ok =
               Vocabulary.validate("event.outing", %{
                 "kind" => "autocross",
                 "sets" => [
                   %{
                     "predicate" => "state.suspension",
                     "value" => %{"summary" => "3.0 deg front camber, 32 psi"}
                   }
                 ]
               })

      # Only state.* traits are settable — not observations, not factory facts.
      assert {:error, _} =
               Vocabulary.validate("event.modification", %{
                 "summary" => "rolled back the odo",
                 "sets" => [%{"predicate" => "observation.mileage", "value" => 1}]
               })

      assert {:error, _} =
               Vocabulary.validate("event.modification", %{
                 "summary" => "repaint",
                 "sets" => [
                   %{
                     "predicate" => "build.paint_code",
                     "value" => %{"code" => "905", "label" => nil}
                   }
                 ]
               })

      # A delta whose value fails its own trait validator fails the event.
      assert {:error, _} =
               Vocabulary.validate("event.modification", %{
                 "summary" => "swap",
                 "sets" => [%{"predicate" => "state.engine", "value" => %{"summary" => nil}}]
               })
    end

    test "logbook predicates carry the scope tenses the fold expects" do
      assert Vocabulary.scope_kind("event.fuel") == :event
      assert Vocabulary.scope_kind("event.modification") == :event
      assert Vocabulary.scope_kind("event.note") == :event
      assert Vocabulary.scope_kind("event.outing") == :event
      assert Vocabulary.scope_kind("state.engine") == :observed
      assert Vocabulary.scope_kind("state.exterior") == :observed
    end
  end

  describe "scope_kind/1" do
    test "identity and build predicates are factory-scoped, observations are observed" do
      assert Vocabulary.scope_kind("identity.marque") == :factory
      assert Vocabulary.scope_kind("build.variant") == :factory
      assert Vocabulary.scope_kind("observation.mileage") == :observed
    end

    test "provenance is factory-tense; service events are event-scoped" do
      assert Vocabulary.scope_kind("build.paint_code") == :factory
      assert Vocabulary.scope_kind("build.production_date") == :factory
      assert Vocabulary.scope_kind("provenance.delivery_dealer") == :factory
      assert Vocabulary.scope_kind("provenance.delivery_date") == :factory
      assert Vocabulary.scope_kind("event.service") == :event
    end

    test "unknown predicate has no scope" do
      assert Vocabulary.scope_kind("legal.lien_holder") == :error
    end
  end

  describe "equivalent?/3" do
    test "paint codes agree on code when both state one, else on label" do
      slate_coa = %{"code" => "59", "label" => "Slate Grey Metallic"}
      slate_sticker = %{"code" => nil, "label" => "Slate Grey Metallic"}
      linden = %{"code" => "226", "label" => "Linden Green"}
      linden_bare = %{"code" => "226", "label" => nil}

      assert Vocabulary.equivalent?("build.paint_code", linden, linden_bare)
      assert Vocabulary.equivalent?("build.paint_code", slate_coa, slate_sticker)
      refute Vocabulary.equivalent?("build.paint_code", slate_coa, linden)
    end
  end
end
