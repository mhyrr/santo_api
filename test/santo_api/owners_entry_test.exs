defmodule SantoApi.OwnersEntryTest do
  @moduledoc """
  The composed entry, and the scope split that governs it (owner_surface §3).

  An owner self-ratifies event- and observed-scope claims on a car they steward:
  nobody on earth is better positioned to vouch for a mod than the person who did
  it, and an operator rubber-stamp would add latency and no epistemics. Factory-
  and provenance-scope claims from the same owner stay proposed, because those
  touch `facts` and the verified display, and owner say-so must not flip a fact
  to verified.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "mhyrr"})
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle)

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user), party: Owners.party(user)}
  end

  describe "compose_entry/3 — the fill-up" do
    test "two claims, one entry_ref, both admitted by the owner", ctx do
      assert {:ok, entry} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 date: ~D[2026-08-02],
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

      assert entry.entry_ref
      assert length(entry.claims) == 2

      for claim <- entry.claims do
        assert claim.entry_ref == entry.entry_ref
        assert claim.state == :admitted
        assert claim.asserted_by_party_id == ctx.party.id
        assert claim.ratified_by_party_id == ctx.party.id
        assert claim.ratified_at
        assert claim.scope_date == ~D[2026-08-02]
        assert claim.method == :human
        assert claim.visibility == :public
      end
    end

    test "presents as one entry on the public timeline, not two", ctx do
      {:ok, _entry} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert length(entry.claims) == 2
      assert entry.party == "mhyrr"
    end

    test "the same fill-up twice in one day is two entries, not one claim", ctx do
      {:ok, first} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())
      {:ok, second} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())

      refute first.entry_ref == second.entry_ref
      assert length(Registry.timeline(ctx.vehicle.id)) == 2
    end

    test "an identical odometer reading is recovered, not duplicated", ctx do
      # `entry_ref` joins the hash for event scope only (§2, ratified), so the
      # two fuel claims are distinct and the one observation is shared: the car
      # read 41,660 once, whatever we were doing when we noticed.
      {:ok, _first} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())
      {:ok, _second} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())

      human = Registry.list_claims(ctx.vehicle.id) |> Enum.filter(&(&1.method == :human))
      assert Enum.count(human, &(&1.predicate == "event.fuel")) == 2
      assert Enum.count(human, &(&1.predicate == "observation.mileage")) == 1
    end

    test "an entry whose claim the operator already rejected does not resurrect it", ctx do
      paint = %{
        date: ~D[2026-08-02],
        claims: [
          %{predicate: "build.paint_code", value: %{"code" => "226", "label" => "Linden Green"}}
        ]
      }

      {:ok, entry} = Owners.compose_entry(ctx.scope, ctx.vehicle, paint)
      [claim] = entry.claims
      {:ok, _rejected} = Registry.reject_claim(claim.id)

      assert {:error, {:claim_not_live, :rejected}} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, paint)
    end

    test "the odometer reading folds into current state", ctx do
      {:ok, _entry} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state["observation.mileage"]["value"] == 41_660
      assert vehicle.current_state["observation.mileage"]["as_of"] == "2026-08-02"
    end
  end

  describe "compose_entry/3 — the scope split (§3)" do
    test "a factory claim from an owner stays proposed for the operator gate", ctx do
      assert {:ok, entry} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 date: ~D[2026-08-02],
                 claims: [
                   %{
                     predicate: "build.paint_code",
                     value: %{"code" => "226", "label" => "Linden Green"}
                   }
                 ]
               })

      assert [claim] = entry.claims
      assert claim.state == :proposed
      assert claim.ratified_by_party_id == nil
      assert claim.asserted_by_party_id == ctx.party.id
    end

    test "an owner's say-so never reads verified", ctx do
      {:ok, _entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{predicate: "build.paint_code", value: %{"code" => "226", "label" => "Linden Green"}}
          ]
        })

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.facts["build.paint_code"]["status"] == "unverified"
    end

    test "a mixed entry splits — the event admits, the factory claim waits", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{predicate: "event.note", value: %{"text" => "found the build sheet"}},
            %{predicate: "build.paint_code", value: %{"code" => "226", "label" => "Linden Green"}}
          ]
        })

      by_predicate = Map.new(entry.claims, &{&1.predicate, &1})
      assert by_predicate["event.note"].state == :admitted
      assert by_predicate["build.paint_code"].state == :proposed

      # Both share the entry_ref, so the operator sees what it was composed with.
      assert by_predicate["event.note"].entry_ref == by_predicate["build.paint_code"].entry_ref
    end
  end

  describe "compose_entry/3 — trait deltas" do
    test "a mod with a sets delta moves current state", ctx do
      {:ok, _entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{
              predicate: "event.modification",
              value: %{
                "summary" => "Wrapped it Signal Green",
                "area" => "exterior",
                "sets" => [
                  %{
                    "predicate" => "state.exterior",
                    "value" => %{"summary" => "Signal Green wrap over Slate Grey"}
                  }
                ]
              }
            }
          ]
        })

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      trait = vehicle.current_state["state.exterior"]
      assert trait["value"]["summary"] == "Signal Green wrap over Slate Grey"
      assert trait["source"] == "event"
      assert trait["as_of"] == "2026-08-02"
    end

    test "a delta targeting something that is not a trait is refused", ctx do
      assert {:error, changeset} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 date: ~D[2026-08-02],
                 claims: [
                   %{
                     predicate: "event.modification",
                     value: %{
                       "summary" => "Repainted",
                       "sets" => [
                         %{"predicate" => "build.paint_code", "value" => %{"code" => "226"}}
                       ]
                     }
                   }
                 ]
               })

      refute changeset.valid?
      assert Registry.timeline(ctx.vehicle.id) == []
    end

    test "a spec-panel trait lands as an observed claim, admitted", ctx do
      {:ok, entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-02],
          claims: [
            %{predicate: "state.engine", value: %{"summary" => "3.4 flat-six, stock"}}
          ]
        })

      assert [claim] = entry.claims
      assert claim.state == :admitted
      assert claim.scope_kind == :observed

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state["state.engine"]["value"]["summary"] == "3.4 flat-six, stock"
    end
  end

  describe "compose_entry/3 — authorization" do
    test "refuses a car the caller does not steward", ctx do
      {:ok, other} = Registry.ingest("WP0CA298X5L001256")

      assert {:error, :not_stewarded} = Owners.compose_entry(ctx.scope, other, fill_up())
      assert Registry.timeline(other.id) == []
    end

    test "refuses a caller with no stewardship at all", ctx do
      stranger = Scope.for_user(user_fixture())

      assert {:error, :not_stewarded} = Owners.compose_entry(stranger, ctx.vehicle, fill_up())
    end

    test "refuses an anonymous caller", ctx do
      assert {:error, :not_stewarded} = Owners.compose_entry(nil, ctx.vehicle, fill_up())
    end

    test "refuses once the stewardship is revoked", ctx do
      stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
      {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "sold the car")

      assert {:error, :not_stewarded} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())
    end
  end

  describe "compose_entry/3 — what it will not accept" do
    test "an entry with no claims is not an entry", ctx do
      assert {:error, :empty_entry} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{date: ~D[2026-08-02], claims: []})
    end

    test "an entry needs a date, because the timeline and the fold both order by it", ctx do
      assert {:error, :missing_date} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 claims: [%{predicate: "event.note", value: %{"text" => "when?"}}]
               })
    end

    test "a predicate outside the vocabulary writes nothing", ctx do
      assert {:error, changeset} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 date: ~D[2026-08-02],
                 claims: [%{predicate: "event.vibes", value: %{"text" => "good"}}]
               })

      refute changeset.valid?
      assert Registry.timeline(ctx.vehicle.id) == []
    end

    test "one bad claim rolls back the whole entry", ctx do
      assert {:error, _changeset} =
               Owners.compose_entry(ctx.scope, ctx.vehicle, %{
                 date: ~D[2026-08-02],
                 claims: [
                   %{predicate: "event.note", value: %{"text" => "this one is fine"}},
                   %{predicate: "observation.mileage", value: -5}
                 ]
               })

      assert Registry.timeline(ctx.vehicle.id) == []
      assert Registry.list_claims(ctx.vehicle.id) |> Enum.filter(&(&1.method == :human)) == []
    end
  end

  describe "compose_entry/3 — photos and visibility" do
    test "photos share the entry's ref and are supplied by the owner", ctx do
      {:ok, entry} =
        Owners.compose_entry(
          ctx.scope,
          ctx.vehicle,
          Map.put(fill_up(), :photos, [photo("receipt.jpg")])
        )

      assert [artifact] = entry.artifacts
      assert artifact.entry_ref == entry.entry_ref
      assert artifact.vehicle_id == ctx.vehicle.id
      assert artifact.kind == :photo
      assert artifact.source_party_id == ctx.party.id
      assert artifact.visibility == :public
    end

    test "a private entry hides its claims and photos from the public timeline", ctx do
      {:ok, entry} =
        Owners.compose_entry(
          ctx.scope,
          ctx.vehicle,
          fill_up() |> Map.put(:visibility, :private) |> Map.put(:photos, [photo("receipt.jpg")])
        )

      assert Enum.all?(entry.claims, &(&1.visibility == :private))
      assert Enum.all?(entry.artifacts, &(&1.visibility == :private))
      assert Registry.timeline(ctx.vehicle.id) == []
    end

    test "a private observation still folds into current state — visibility is not admission",
         ctx do
      {:ok, _entry} =
        Owners.compose_entry(
          ctx.scope,
          ctx.vehicle,
          Map.put(fill_up(), :visibility, :private)
        )

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.current_state["observation.mileage"]["value"] == 41_660
    end
  end

  describe "timeline/2 — the owner's own view" do
    test "the steward sees the entry they hid; nobody else does", ctx do
      {:ok, _entry} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, Map.put(fill_up(), :visibility, :private))

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert entry.visibility == :private

      assert Owners.timeline(Scope.for_user(user_fixture()), ctx.vehicle) == []
      assert Owners.timeline(nil, ctx.vehicle) == []
    end

    test "a revoked steward loses the private view but keeps the public one", ctx do
      {:ok, _private} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, Map.put(fill_up(), :visibility, :private))

      {:ok, _public} =
        Owners.compose_entry(ctx.scope, ctx.vehicle, %{
          date: ~D[2026-08-03],
          claims: [%{predicate: "event.note", value: %{"text" => "washed it"}}]
        })

      stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
      {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "sold the car")

      assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
      assert entry.visibility == :public
    end
  end

  describe "last_entry_defaults/2" do
    test "is empty for a car with no entries", ctx do
      assert Owners.last_entry_defaults(ctx.scope, ctx.vehicle) == %{}
    end

    test "carries the last odometer forward so the next fill-up is three numbers", ctx do
      {:ok, _entry} = Owners.compose_entry(ctx.scope, ctx.vehicle, fill_up())

      defaults = Owners.last_entry_defaults(ctx.scope, ctx.vehicle)
      assert defaults.odometer == 41_660
      assert defaults.volume == "13.1"
      assert defaults.unit == "gal"
    end
  end

  defp fill_up do
    %{
      date: ~D[2026-08-02],
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
    }
  end

  defp photo(filename) do
    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, "photo bytes #{System.unique_integer([:positive])}")
    %{path: path, filename: filename, mime: "image/jpeg"}
  end
end
