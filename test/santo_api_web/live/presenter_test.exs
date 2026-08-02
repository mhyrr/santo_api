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
  end
end
