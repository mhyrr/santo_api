defmodule SantoApiWeb.VehicleLive.PresenterTest do
  @moduledoc """
  The naming rules, which are judgment calls and worth pinning.
  """
  use ExUnit.Case, async: true

  alias SantoApi.Registry.Vehicle
  alias SantoApiWeb.VehicleLive.Presenter

  defp vehicle(facts, attrs \\ []) do
    struct(
      %Vehicle{
        identity_kind: :vin,
        identity_key: "vin:WP0AB29827U782968",
        facts: facts,
        current_state: %{}
      },
      attrs
    )
  end

  defp fact(value), do: %{"value" => value, "status" => "verified"}

  describe "title/1" do
    test "reads year, marque and model when the decode supplies them" do
      title =
        vehicle(%{
          "identity.model_year" => fact(2007),
          "identity.marque" => fact("porsche"),
          "identity.model" => fact(%{"code" => "cayman", "label" => nil})
        })
        |> Presenter.title()

      assert title == "2007 Porsche Cayman"
    end

    test "prefers santo's code when a source labelled the model with a type number" do
      title =
        vehicle(%{
          "identity.model_year" => fact(2005),
          "identity.marque" => fact("porsche"),
          "identity.model" => fact(%{"code" => "carrera_gt", "label" => "980"})
        })
        |> Presenter.title()

      # "980" is the factory type number, not what anyone calls the car.
      assert title == "2005 Porsche Carrera GT"
    end

    test "keeps the generation when that is what the car is called" do
      title =
        vehicle(%{
          "identity.model_year" => fact(1996),
          "identity.marque" => fact("porsche"),
          "identity.model" => fact(%{"code" => "911", "label" => "993"})
        })
        |> Presenter.title()

      # A 993 is a 911, but "993" is the more specific name and the one used.
      assert title == "1996 Porsche 993"
    end

    test "keeps a real label over the code" do
      title =
        vehicle(%{"identity.model" => fact(%{"code" => "f355", "label" => "F355 Berlinetta"})})
        |> Presenter.title()

      assert title == "F355 Berlinetta"
    end

    test "an undecodable chassis is named by its number, not called unidentified" do
      title =
        vehicle(%{}, identity_kind: :chassis, identity_key: "chassis:ferrari:pre_vin:19425")
        |> Presenter.title()

      assert title == "Ferrari chassis 19425"
    end

    test "falls back to the marque alone rather than inventing a name" do
      assert Presenter.title(vehicle(%{"identity.marque" => fact("porsche")})) == "Porsche"
    end
  end

  describe "marque/1" do
    test "comes from the record when there is one" do
      assert Presenter.marque(vehicle(%{"identity.marque" => fact("ferrari")})) == "Ferrari"
    end

    test "comes from the identity key for a pre-standard chassis" do
      assert Presenter.marque(
               vehicle(%{},
                 identity_kind: :chassis,
                 identity_key: "chassis:ferrari:pre_vin:19425"
               )
             ) == "Ferrari"
    end

    test "is nil when nothing says — the caller decides what to print" do
      assert Presenter.marque(vehicle(%{})) == nil
    end
  end

  describe "entry_parts/1" do
    test "a spec entry has no headline of its own, so every trait gets a line" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{predicate: "state.engine", value: %{"summary" => "3.4 flat-six, stock"}},
            %{predicate: "state.wheels_tires", value: %{"summary" => "19x8 / 19x9.5"}}
          ]
        })

      assert parts.headline == "Spec recorded"

      assert parts.details == [
               %{label: "Engine", value: "3.4 flat-six, stock"},
               %{label: "Wheels & tires", value: "19x8 / 19x9.5"}
             ]
    end

    test "a fill-up leads with what happened and keeps the reading as a detail" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.1", "unit" => "gal"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      assert parts.headline == "13.1 gal of fuel"
      assert parts.details == [%{label: "Odometer", value: "41,660 mi"}]
    end

    test "a mod leads with the owner's own words" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.modification",
              value: %{"summary" => "Wrapped it Signal Green", "sets" => []}
            }
          ]
        })

      assert parts.headline == "Wrapped it Signal Green"
      assert parts.details == []
    end

    test "a completed auction event reads as a sale" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.sale",
              value: %{"venue" => "RM Auctions", "price" => 352_000, "currency" => "USD"}
            }
          ]
        })

      assert parts.headline == "Sold at RM Auctions for $352,000"
      assert parts.details == []
    end

    test "an unsuccessful auction event reads as a high bid, never a sale" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.sale",
              value: %{
                "venue" => "Mecum Auctions",
                "price" => 55_000,
                "currency" => "USD",
                "outcome" => "not_sold"
              }
            }
          ]
        })

      assert parts.headline == "High bid of $55,000 at Mecum Auctions; not sold"
      refute parts.headline =~ "Sold at"
      assert parts.details == []
    end

    test "words we could not structure are shown, not just kept" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.1", "unit" => "gal"}},
            %{predicate: "event.note", value: %{"text" => "cost: about sixty bucks; pump: 4"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      assert parts.headline == "13.1 gal of fuel"

      assert parts.details == [
               %{label: "Note", value: "cost: about sixty bucks; pump: 4"},
               %{label: "Odometer", value: "41,660 mi"}
             ]
    end

    test "a residual note never outranks the event it was salvaged from" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{predicate: "event.note", value: %{"text" => "pump: 4"}},
            %{predicate: "event.fuel", value: %{"volume" => "13.1", "unit" => "gal"}}
          ]
        })

      assert parts.headline == "13.1 gal of fuel"
      assert parts.details == [%{label: "Note", value: "pump: 4"}]
    end

    test "a note that is the whole entry still leads with the owner's words" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{predicate: "event.note", value: %{"text" => "Sat in the garage all winter"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      assert parts.headline == "Sat in the garage all winter"
      assert parts.details == [%{label: "Odometer", value: "41,660 mi"}]
    end

    test "a plan is explicit about intent" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.plan",
              value: %{"text" => "Try lighter wheels", "area" => "Wheels & tires"}
            }
          ]
        })

      assert parts.headline == "Planned: Try lighter wheels"
      assert parts.details == [%{label: "Plan", value: "Wheels & tires"}]
    end

    test "a fill-up shows what it cost" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.fuel",
              value: %{
                "volume" => "13.1",
                "unit" => "gal",
                "total_cents" => 6745,
                "currency" => "USD"
              }
            },
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      assert parts.headline == "13.1 gal of fuel"
      assert %{label: "Total", value: "$67.45"} in parts.details
      assert %{label: "Odometer", value: "41,660 mi"} in parts.details
    end

    test "the price per gallon is derived from the two measurements" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.fuel",
              value: %{
                "volume" => "13.1",
                "unit" => "gal",
                "total_cents" => 6745,
                "currency" => "USD"
              }
            }
          ]
        })

      # $67.45 over 13.1 gallons is $5.148854…, which no fixed precision holds.
      # The ledger keeps the two measurements; this is the quotient, rounded
      # freely because nobody reconciles a price per gallon.
      assert %{label: "Price", value: "$5.15/gal"} in parts.details
    end

    test "litres are priced per litre, not per gallon" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.fuel",
              value: %{
                "volume" => "40.0",
                "unit" => "l",
                "total_cents" => 7000,
                "currency" => "EUR"
              }
            }
          ]
        })

      assert %{label: "Price", value: "1.75 EUR/L"} in parts.details
    end

    test "a fill-up with no volume to divide by shows a total and no ratio" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.fuel",
              value: %{
                "volume" => "0",
                "unit" => "gal",
                "total_cents" => 500,
                "currency" => "USD"
              }
            }
          ]
        })

      assert %{label: "Total", value: "$5.00"} in parts.details
      refute Enum.any?(parts.details, &(&1.label == "Price"))
    end

    test "a fill-up nobody priced says nothing about money" do
      parts =
        Presenter.entry_parts(%{
          claims: [%{predicate: "event.fuel", value: %{"volume" => "13.1", "unit" => "gal"}}]
        })

      assert parts.headline == "13.1 gal of fuel"
      assert parts.details == []
    end

    test "a total whose currency nobody stated is not silently dollars" do
      parts =
        Presenter.entry_parts(%{
          claims: [
            %{
              predicate: "event.fuel",
              value: %{"volume" => "40.0", "unit" => "l", "total_cents" => 7000}
            }
          ]
        })

      assert %{label: "Total", value: "70.00"} in parts.details
      refute Enum.any?(parts.details, &String.contains?(&1.value, "$"))
    end

    test "a lead whose second fact is missing gets no line rather than an empty one" do
      parts =
        Presenter.entry_parts(%{
          claims: [%{predicate: "event.service", value: %{"summary" => "Oil change"}}]
        })

      assert parts.headline == "Oil change"
      assert parts.details == []
    end
  end

  describe "record_rows/2" do
    test "keeps the projected value while formatting every contributing claim" do
      vehicle =
        vehicle(%{
          "identity.model" => %{
            "value" => %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"},
            "status" => "conflicted"
          }
        })

      provenance = %{
        "identity.model" => %{
          claims: [
            %{
              claim_id: "claim-one",
              value: %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"},
              party: "RM Auctions",
              state: :proposed,
              scope_date: nil,
              artifact: %{kind: :reference, acquired_at: ~U[2026-08-04 12:00:00.000000Z]}
            },
            %{
              claim_id: "claim-two",
              value: %{"code" => "dino_246_gt", "label" => "Dino 246 GT"},
              party: "Bring a Trailer",
              state: :proposed,
              scope_date: nil,
              artifact: nil
            }
          ],
          sources: [
            %{url: "https://example.com/dino", parties: ["RM Auctions"]}
          ]
        }
      }

      assert [row] = Presenter.record_rows(vehicle, provenance)
      assert row.value == "Dino 246 GTS"
      assert row.status == "conflicted"
      assert row.dom_id == "fact-identity-model"

      assert Enum.map(row.claims, & &1.value) ==
               ["Dino 246 GTS", "Dino 246 GT"]

      assert [%{label: "RM Auctions", dom_id: source_id}] = row.sources
      assert String.starts_with?(source_id, "fact-identity-model-source-")
    end
  end
end
