defmodule SantoApi.RegistryCurrentStateTest do
  @moduledoc """
  The current-state fold (TK-010, owner_surface §2b): what is the car *now*,
  derived from the ledger and never from the factory record.
  """
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.{Claim, Vehicle}

  @nine_three "WP0ZZZ99ZTS392124"

  defp admit(vehicle, attrs) do
    {:ok, claim} = Registry.propose_claim(vehicle, attrs)
    {:ok, admitted} = Registry.ratify_claim(claim.id)
    admitted
  end

  defp current_state(vehicle) do
    {:ok, reloaded} = Registry.fetch_vehicle(vehicle.id)
    reloaded.current_state
  end

  defp engine(summary), do: %{"summary" => summary}

  describe "observed trait claims" do
    test "an admitted trait claim becomes the current state, dated" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      claim =
        admit(vehicle, %{
          predicate: "state.engine",
          value: engine("3.6 flat-six, original"),
          scope_date: ~D[2024-03-01]
        })

      assert %{"state.engine" => entry} = current_state(vehicle)
      assert entry["value"] == engine("3.6 flat-six, original")
      assert entry["as_of"] == "2024-03-01"
      assert entry["source"] == "observed"
      assert entry["claim_id"] == claim.id
    end

    test "observation.mileage folds like any other observed trait" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "observation.mileage",
        value: 88_000,
        scope_date: ~D[2025-01-01]
      })

      assert current_state(vehicle)["observation.mileage"]["value"] == 88_000
    end

    test "a proposed claim never folds — the confirm gate has to keep meaning something" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, _proposed} =
        Registry.propose_claim(vehicle, %{
          predicate: "state.engine",
          value: engine("LS1, allegedly"),
          scope_date: ~D[2025-06-01]
        })

      refute Map.has_key?(current_state(vehicle), "state.engine")
    end

    test "a rejected claim drops back out of the fold" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, claim} =
        Registry.propose_claim(vehicle, %{
          predicate: "state.wheels_tires",
          value: %{"summary" => "wrong wheels"},
          scope_date: ~D[2025-06-01]
        })

      {:ok, _rejected} = Registry.reject_claim(claim.id)

      refute Map.has_key?(current_state(vehicle), "state.wheels_tires")
    end

    test "a private claim still folds — visibility is presentation, not admission" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      claim = admit(vehicle, %{predicate: "state.brakes", value: %{"summary" => "PCCB"}})

      {:ok, _hidden} = Registry.set_visibility(claim, :private)
      Registry.refresh_projections(vehicle)

      assert current_state(vehicle)["state.brakes"]["value"] == %{"summary" => "PCCB"}
    end
  end

  describe "precedence" do
    test "the latest scope date wins" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("stock"),
        scope_date: ~D[2020-01-01]
      })

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("built 3.8"),
        scope_date: ~D[2024-01-01]
      })

      assert current_state(vehicle)["state.engine"]["value"] == engine("built 3.8")
      assert current_state(vehicle)["state.engine"]["as_of"] == "2024-01-01"
    end

    test "an earlier claim recorded later does not win" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("built 3.8"),
        scope_date: ~D[2024-01-01]
      })

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("stock"),
        scope_date: ~D[2020-01-01]
      })

      assert current_state(vehicle)["state.engine"]["value"] == engine("built 3.8")
    end

    test "same-date ties break to the latest insertion — the inverse of facts" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      date = ~D[2024-05-05]

      admit(vehicle, %{
        predicate: "state.exterior",
        value: %{"summary" => "first"},
        scope_date: date
      })

      admit(vehicle, %{
        predicate: "state.exterior",
        value: %{"summary" => "corrected"},
        scope_date: date
      })

      assert current_state(vehicle)["state.exterior"]["value"] == %{"summary" => "corrected"}
    end

    test "an undated observation loses to a dated one" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      admit(vehicle, %{predicate: "state.suspension", value: %{"summary" => "undated"}})

      admit(vehicle, %{
        predicate: "state.suspension",
        value: %{"summary" => "dated"},
        scope_date: ~D[2019-01-01]
      })

      assert current_state(vehicle)["state.suspension"]["value"] == %{"summary" => "dated"}
    end
  end

  describe "event deltas" do
    test "an admitted event's sets deltas set the trait, dated at the event" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      event =
        admit(vehicle, %{
          predicate: "event.modification",
          value: %{
            "summary" => "LS1 swap",
            "area" => "engine",
            "sets" => [%{"predicate" => "state.engine", "value" => engine("LS1, 5.7L")}]
          },
          scope_date: ~D[2025-04-12]
        })

      entry = current_state(vehicle)["state.engine"]

      assert entry["value"] == engine("LS1, 5.7L")
      assert entry["as_of"] == "2025-04-12"
      assert entry["source"] == "event"
      assert entry["claim_id"] == event.id
    end

    test "a proposed event's deltas never fold" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, _proposed} =
        Registry.propose_claim(vehicle, %{
          predicate: "event.outing",
          value: %{
            "kind" => "autocross",
            "sets" => [
              %{"predicate" => "state.suspension", "value" => %{"summary" => "3 deg camber"}}
            ]
          },
          scope_date: ~D[2025-07-01]
        })

      refute Map.has_key?(current_state(vehicle), "state.suspension")
    end

    test "a later observation overrides an event delta, and the event overrides an older one" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "state.wheels_tires",
        value: %{"summary" => "stock 18s"},
        scope_date: ~D[2023-01-01]
      })

      admit(vehicle, %{
        predicate: "event.modification",
        value: %{
          "summary" => "18x11 rears",
          "sets" => [%{"predicate" => "state.wheels_tires", "value" => %{"summary" => "18x11"}}]
        },
        scope_date: ~D[2024-01-01]
      })

      assert current_state(vehicle)["state.wheels_tires"]["value"] == %{"summary" => "18x11"}

      admit(vehicle, %{
        predicate: "state.wheels_tires",
        value: %{"summary" => "back to stock"},
        scope_date: ~D[2025-01-01]
      })

      assert current_state(vehicle)["state.wheels_tires"]["value"] == %{
               "summary" => "back to stock"
             }
    end

    test "an event with no sets stays timeline-only" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "event.note",
        value: %{"text" => "washed it"},
        scope_date: ~D[2025-02-02]
      })

      assert current_state(vehicle) == %{}
    end
  end

  describe "independence from the factory record" do
    test "a car with no factory record at all still has a current state" do
      {:ok, vehicle} = Registry.register_chassis(:porsche, :pre_vin, "9113600123")

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("LS1 swap, 5.7L"),
        scope_date: ~D[2024-08-01]
      })

      {:ok, reloaded} = Registry.fetch_vehicle(vehicle.id)

      assert reloaded.facts == %{}
      assert reloaded.current_state["state.engine"]["value"] == engine("LS1 swap, 5.7L")
    end

    test "factory claims never leak into current state" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      admit(vehicle, %{predicate: "build.variant", value: "coupe"})

      assert current_state(vehicle) == %{}
      assert Map.has_key?(elem(Registry.fetch_vehicle(vehicle.id), 1).facts, "build.variant")
    end
  end

  describe "replay" do
    test "dropping the column and re-folding from the ledger reproduces it exactly" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      admit(vehicle, %{
        predicate: "state.engine",
        value: engine("stock"),
        scope_date: ~D[2020-01-01]
      })

      admit(vehicle, %{
        predicate: "event.modification",
        value: %{
          "summary" => "LS1 swap",
          "sets" => [%{"predicate" => "state.engine", "value" => engine("LS1, 5.7L")}]
        },
        scope_date: ~D[2024-06-01]
      })

      admit(vehicle, %{
        predicate: "observation.mileage",
        value: 112_500,
        scope_date: ~D[2025-05-05]
      })

      admit(vehicle, %{
        predicate: "state.wheels_tires",
        value: %{"summary" => "18x11 rears"},
        scope_date: ~D[2024-06-01]
      })

      rejected_claim =
        elem(
          Registry.propose_claim(vehicle, %{
            predicate: "state.brakes",
            value: %{"summary" => "never happened"},
            scope_date: ~D[2026-01-01]
          }),
          1
        )

      {:ok, _} = Registry.reject_claim(rejected_claim.id)

      before = current_state(vehicle)
      assert map_size(before) == 3

      Repo.update_all(Vehicle, set: [current_state: %{}])
      assert current_state(vehicle) == %{}

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      Registry.refresh_projections(vehicle)

      assert current_state(vehicle) == before
    end

    test "the fold survives a claim being superseded out from under it" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      claim =
        admit(vehicle, %{
          predicate: "state.engine",
          value: engine("wrong"),
          scope_date: ~D[2025-01-01]
        })

      Repo.update!(Ecto.Changeset.change(Repo.get!(Claim, claim.id), state: :superseded))
      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      Registry.refresh_projections(vehicle)

      assert current_state(vehicle) == %{}
    end
  end
end
