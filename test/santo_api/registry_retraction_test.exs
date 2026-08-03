defmodule SantoApi.RegistryRetractionTest do
  @moduledoc """
  Withdrawing your own claim (contract §3, owner_surface §8).

  The third correction mode, alongside the ratification gate and adjudication.
  Adjudication settles a dispute *between* parties and demands evidence;
  retraction is one party withdrawing their own assertion, which is not a
  dispute and has no evidence to produce. The ledger keeps the row either way.
  """

  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.Claim

  @nine_three "WP0ZZZ99ZTS392124"

  defp owner_claim(vehicle, party, attrs) do
    {:ok, claim} = Registry.propose_claim(vehicle, party, attrs)
    claim
  end

  describe "retract_claim/2" do
    test "flips an admitted claim to :retracted with who and when" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      claim = owner_claim(vehicle, owner, %{predicate: "observation.mileage", value: 12_000})
      {:ok, admitted} = Registry.ratify_claim(claim.id, owner)

      {:ok, retracted} = Registry.retract_claim(admitted.id, owner)

      assert retracted.state == :retracted
      assert retracted.retracted_by_party_id == owner.id
      assert %DateTime{} = retracted.retracted_at

      # Ratification attribution survives the retraction. The claim *was*
      # admitted, by somebody, on a date; withdrawing it later does not unmake
      # that, and an append-only ledger has no business forgetting it.
      assert retracted.ratified_by_party_id == owner.id
      assert retracted.ratified_at == admitted.ratified_at
    end

    test "retracts a proposed claim that never entered the record" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)

      claim =
        owner_claim(vehicle, owner, %{
          predicate: "build.paint_code",
          value: %{"code" => "226", "label" => "Linden Green"}
        })

      assert claim.state == :proposed
      assert {:ok, %Claim{state: :retracted}} = Registry.retract_claim(claim.id, owner)
    end

    test "keeps the row and its content hash — nothing is deleted" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      claim = owner_claim(vehicle, owner, %{predicate: "observation.mileage", value: 12_000})

      {:ok, retracted} = Registry.retract_claim(claim.id, owner)

      assert Repo.get(Claim, claim.id)
      assert retracted.content_hash == claim.content_hash
      assert retracted.value == claim.value
    end

    test "only the asserting party may withdraw an assertion" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      stranger = Registry.ensure_party("someone-else", :owner)
      claim = owner_claim(vehicle, owner, %{predicate: "observation.mileage", value: 12_000})

      assert {:error, :not_asserting_party} = Registry.retract_claim(claim.id, stranger)
      assert Repo.get(Claim, claim.id).state == :proposed
    end

    test "refuses a claim that is already retracted, superseded, or rejected" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      claim = owner_claim(vehicle, owner, %{predicate: "observation.mileage", value: 12_000})

      {:ok, _} = Registry.retract_claim(claim.id, owner)
      assert {:error, {:not_live, :retracted}} = Registry.retract_claim(claim.id, owner)
    end

    test "refuses an unknown claim without raising" do
      owner = Registry.ensure_party("jean", :owner)

      assert {:error, :not_found} = Registry.retract_claim(Ecto.UUID.generate(), owner)
      assert {:error, :not_found} = Registry.retract_claim("not-a-uuid", owner)
    end
  end

  describe "retraction and the projections" do
    test "a retracted observation drops out of current_state" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      claim = owner_claim(vehicle, owner, %{predicate: "observation.mileage", value: 12_000})
      {:ok, admitted} = Registry.ratify_claim(claim.id, owner)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      assert get_in(vehicle.current_state, ["observation.mileage", "value"]) == 12_000

      {:ok, _} = Registry.retract_claim(admitted.id, owner)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      refute Map.has_key?(vehicle.current_state, "observation.mileage")
    end

    test "a retracted factory claim drops out of facts" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)

      claim =
        owner_claim(vehicle, owner, %{
          predicate: "build.paint_code",
          value: %{"code" => "226", "label" => "Linden Green"}
        })

      {:ok, admitted} = Registry.ratify_claim(claim.id)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      assert get_in(vehicle.facts, ["build.paint_code", "value", "code"]) == "226"

      {:ok, _} = Registry.retract_claim(admitted.id, owner)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      refute Map.has_key?(vehicle.facts, "build.paint_code")
    end

    test "a retracted claim leaves the timeline" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("jean", :owner)
      entry_ref = Registry.new_entry_ref()

      claim =
        owner_claim(vehicle, owner, %{
          predicate: "event.note",
          value: %{"text" => "changed the camber"},
          scope_date: ~D[2026-07-01],
          entry_ref: entry_ref
        })

      {:ok, admitted} = Registry.ratify_claim(claim.id, owner)

      assert [%{entry_ref: ^entry_ref}] = Registry.timeline(vehicle.id)

      {:ok, _} = Registry.retract_claim(admitted.id, owner)

      assert Registry.timeline(vehicle.id) == []
    end
  end
end
