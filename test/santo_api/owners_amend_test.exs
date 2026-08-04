defmodule SantoApi.OwnersAmendTest do
  @moduledoc """
  Correcting what you logged (owner_surface §8, decided 2026-08-03).

  The rule Greg set: whatever the owner puts in is right, and anything they put
  in they can change later. The line is the *asserting party*, not the scope
  kind — a claim is yours to revise because you made it, not because of what it
  is about. Claims from santo, vPIC, or any provider are untouchable here;
  a conflict with those produces both sources, not an edit.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture()
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle, handle: "mhyrr")

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user), party: Owners.party(user)}
  end

  defp fuel_entry(ctx, volume) do
    {:ok, entry} =
      Owners.compose_entry(ctx.scope, ctx.vehicle, %{
        date: ~D[2026-08-02],
        claims: [
          %{
            predicate: "event.fuel",
            value: %{"volume" => volume, "unit" => "gal", "cost" => "67.45", "currency" => "USD"}
          },
          %{predicate: "observation.mileage", value: 41_660}
        ]
      })

    entry
  end

  defp live_claims(vehicle, entry_ref) do
    Repo.all(
      from(c in Claim,
        where:
          c.vehicle_id == ^vehicle.id and c.entry_ref == ^entry_ref and
            c.state in [:proposed, :admitted]
      )
    )
  end

  describe "amend_entry/4" do
    test "replaces the claim that changed and leaves the one that did not", ctx do
      entry = fuel_entry(ctx, "13.1")

      assert {:ok, amended} =
               Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
                 claims: [
                   %{
                     predicate: "event.fuel",
                     value: %{
                       "volume" => "13.5",
                       "unit" => "gal",
                       "cost" => "67.45",
                       "currency" => "USD"
                     }
                   },
                   %{predicate: "observation.mileage", value: 41_660}
                 ]
               })

      assert amended.entry_ref == entry.entry_ref

      values =
        ctx.vehicle
        |> live_claims(entry.entry_ref)
        |> Map.new(&{&1.predicate, &1.value})

      assert values["event.fuel"]["volume"] == "13.5"
      assert values["observation.mileage"] == 41_660

      # The unchanged odometer was never wrong, so it is the same row — an
      # amendment that churned every claim would attribute a fresh assertion
      # to the owner for something they never restated.
      unchanged = Enum.find(entry.claims, &(&1.predicate == "observation.mileage"))
      still_live = Enum.find(live_claims(ctx.vehicle, entry.entry_ref), &(&1.id == unchanged.id))
      assert still_live.state == :admitted
    end

    test "the superseded value is retracted, not deleted", ctx do
      entry = fuel_entry(ctx, "13.1")
      original = Enum.find(entry.claims, &(&1.predicate == "event.fuel"))

      {:ok, _} =
        Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.5", "unit" => "gal"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      withdrawn = Repo.get!(Claim, original.id)
      assert withdrawn.state == :retracted
      assert withdrawn.retracted_by_party_id == ctx.party.id
      assert withdrawn.value["volume"] == "13.1"
    end

    test "the timeline shows one entry with the corrected value", ctx do
      entry = fuel_entry(ctx, "13.1")

      {:ok, _} =
        Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.5", "unit" => "gal"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      assert [timeline_entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert timeline_entry.entry_ref == entry.entry_ref

      volumes =
        for c <- timeline_entry.claims, c.predicate == "event.fuel", do: c.value["volume"]

      assert volumes == ["13.5"]
    end

    test "undoing a correction revives the owner's own withdrawn claim", ctx do
      entry = fuel_entry(ctx, "13.1")
      original = Enum.find(entry.claims, &(&1.predicate == "event.fuel"))

      correction = %{
        claims: [
          %{predicate: "event.fuel", value: %{"volume" => "13.5", "unit" => "gal"}},
          %{predicate: "observation.mileage", value: 41_660}
        ]
      }

      {:ok, _} = Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, correction)

      # Changing your mind back. The content hash of the original assertion is
      # still held by the retracted row, so this only works if re-asserting
      # revives it rather than colliding with it.
      assert {:ok, _} =
               Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
                 claims: [
                   %{
                     predicate: "event.fuel",
                     value: %{
                       "volume" => "13.1",
                       "unit" => "gal",
                       "cost" => "67.45",
                       "currency" => "USD"
                     }
                   },
                   %{predicate: "observation.mileage", value: 41_660}
                 ]
               })

      assert Repo.get!(Claim, original.id).state == :admitted
    end

    test "an entry kept off the public page stays off it through a correction", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          visibility: :private,
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.1", "unit" => "gal"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      {:ok, _} =
        Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
          claims: [
            %{predicate: "event.fuel", value: %{"volume" => "13.5", "unit" => "gal"}},
            %{predicate: "observation.mileage", value: 41_660}
          ]
        })

      # Visibility is the entry's, not the claim's, and correcting a value is
      # not consent to publish. A claim written by an amendment takes the
      # default `:public` unless the amendment carries the entry's own setting
      # forward — which is how a typo fix could quietly put a private entry on
      # the public page.
      for claim <- live_claims(ctx.vehicle, entry.entry_ref) do
        assert claim.visibility == :private
      end
    end

    test "a factory claim the owner typed is theirs to correct too", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "build.paint_code",
              value: %{"code" => "226", "label" => "Linden Green"}
            }
          ]
        })

      # Still proposed — the scope split is untouched by any of this. Editing
      # governs who may revise an assertion; ratification governs when one
      # enters the record. They do not interact.
      assert [%Claim{state: :proposed}] = live_claims(ctx.vehicle, entry.entry_ref)

      assert {:ok, _} =
               Owners.amend_entry(ctx.scope, ctx.vehicle, entry.entry_ref, %{
                 claims: [
                   %{
                     predicate: "build.paint_code",
                     value: %{"code" => "L20B", "label" => "Signal Green"}
                   }
                 ]
               })

      assert [%Claim{state: :proposed, value: value}] = live_claims(ctx.vehicle, entry.entry_ref)
      assert value["code"] == "L20B"
    end
  end

  describe "what an owner may not touch" do
    test "santo's own decode claims are not the owner's to amend", ctx do
      santo_claim =
        Repo.one!(
          from(c in Claim,
            where: c.vehicle_id == ^ctx.vehicle.id and c.method == :santo,
            limit: 1
          )
        )

      assert {:error, :not_asserting_party} =
               Owners.retract_claim(ctx.scope, ctx.vehicle, santo_claim.id)

      assert Repo.get!(Claim, santo_claim.id).state == :admitted
    end

    test "a car you do not steward refuses both paths", ctx do
      entry = fuel_entry(ctx, "13.1")
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} =
               Owners.amend_entry(stranger, ctx.vehicle, entry.entry_ref, %{
                 claims: [%{predicate: "observation.mileage", value: 99_999}]
               })

      assert {:error, :not_stewarded} =
               Owners.retract_entry(stranger, ctx.vehicle, entry.entry_ref)
    end

    test "an unknown entry_ref refuses rather than writing a new entry", ctx do
      assert {:error, :entry_not_found} =
               Owners.amend_entry(ctx.scope, ctx.vehicle, Registry.new_entry_ref(), %{
                 claims: [%{predicate: "observation.mileage", value: 99_999}]
               })
    end
  end

  describe "retract_entry/3" do
    test "withdraws every claim of the entry and clears it from the timeline", ctx do
      entry = fuel_entry(ctx, "13.1")

      assert {:ok, 2} = Owners.retract_entry(ctx.scope, ctx.vehicle, entry.entry_ref)

      assert live_claims(ctx.vehicle, entry.entry_ref) == []
      assert Owners.timeline(ctx.scope, ctx.vehicle) == []

      for claim <- entry.claims do
        assert Repo.get!(Claim, claim.id).state == :retracted
      end
    end

    test "drops the entry's reading out of current_state", ctx do
      entry = fuel_entry(ctx, "13.1")

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert get_in(vehicle.current_state, ["observation.mileage", "value"]) == 41_660

      {:ok, _} = Owners.retract_entry(ctx.scope, ctx.vehicle, entry.entry_ref)

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      refute Map.has_key?(vehicle.current_state, "observation.mileage")
    end
  end
end
