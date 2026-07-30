defmodule SantoApi.RegistryTest do
  use SantoApi.DataCase, async: true

  alias SantoApi.Registry
  alias SantoApi.Registry.{Claim, EvidenceRequest, Vehicle}

  @cgt "WP0CA298X5L001502"
  @nine_five_nine "WP0ZZZ95ZJS905016"
  @disputed_chassis "81192"

  describe "ingest/1 with a resolvable VIN" do
    test "persists the vehicle keyed by identity, with decode snapshot and santo version" do
      assert {:ok, %Vehicle{} = vehicle} = Registry.ingest(@nine_five_nine)

      assert vehicle.identity_kind == :vin
      assert vehicle.identity_key == "vin:WP0ZZZ95ZJS905016"
      assert vehicle.candidates == []
      assert vehicle.input == @nine_five_nine
      assert vehicle.santo_version == "0.2.0"
      assert %{"marque" => "porsche"} = vehicle.decode_snapshot
    end

    test "emits admitted factory claims for every mapped decode fact" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      claims = Registry.list_claims(vehicle.id)

      assert Enum.map(claims, &{&1.predicate, &1.value}) |> Enum.sort() ==
               Enum.sort([
                 {"identity.marque", "porsche"},
                 {"identity.model", %{"code" => "959", "label" => "959"}},
                 {"identity.model_year", 1988},
                 {"identity.market", "row"},
                 {"build.plant", "Stuttgart-Zuffenhausen"},
                 {"build.variant", "sport"}
               ])

      vin_santo = Registry.vin_santo_party()

      for %Claim{} = claim <- claims do
        assert claim.state == :admitted
        assert claim.method == :santo
        assert claim.scope_kind == :factory
        assert claim.asserted_by_party_id == vin_santo.id
        assert is_binary(claim.content_hash)
      end
    end

    test "facts materialize as the one-row view, all verified for santo-only claims" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      assert map_size(vehicle.facts) == 6

      assert vehicle.facts["identity.model_year"] == %{"value" => 1988, "status" => "verified"}

      assert vehicle.facts["build.variant"] == %{"value" => "sport", "status" => "verified"}

      assert Enum.all?(vehicle.facts, fn {_predicate, fact} ->
               fact["status"] == "verified"
             end)
    end

    test "unmapped decode attributes stay in the snapshot without claims" do
      {:ok, vehicle} = Registry.ingest(@cgt)

      claims = Registry.list_claims(vehicle.id)
      predicates = Enum.map(claims, & &1.predicate)

      assert "identity.model" in predicates
      refute "build.variant" in predicates
      assert vehicle.decode_snapshot["attributes"]["engine_code"] == "A"
      assert Registry.list_evidence_requests(vehicle.id) == []
    end
  end

  describe "ingest/1 with a disputed identity" do
    test "stores one row with candidates as data and no claims" do
      assert {:ok, %Vehicle{} = vehicle} = Registry.ingest(@disputed_chassis)

      assert vehicle.identity_kind == :disputed

      assert vehicle.candidates == [
               "chassis:porsche:356_pre_a:81192",
               "chassis:porsche:356_a:81192"
             ]

      assert Registry.list_claims(vehicle.id) == []
      assert vehicle.facts == %{}
    end

    test "opens an identity evidence request carrying santo's evidence classes" do
      {:ok, vehicle} = Registry.ingest(@disputed_chassis)

      assert [%EvidenceRequest{} = request] = Registry.list_evidence_requests(vehicle.id)
      assert request.subject == "identity"
      assert request.status == :open
      assert Enum.sort(request.evidence_classes) == ["engine_number", "kardex"]
    end
  end

  describe "ingest/1 idempotency" do
    test "re-ingesting the same identity returns the same row without duplicating anything" do
      {:ok, first} = Registry.ingest(@disputed_chassis)
      {:ok, second} = Registry.ingest(@disputed_chassis)

      assert first.id == second.id
      assert length(Registry.list_evidence_requests(first.id)) == 1

      {:ok, v1} = Registry.ingest(@nine_five_nine)
      {:ok, v2} = Registry.ingest(@nine_five_nine)

      assert v1.id == v2.id
      assert length(Registry.list_claims(v1.id)) == 6
    end
  end

  describe "ingest/1 with invalid input" do
    test "passes santo's diagnosis through and persists nothing" do
      assert {:error, %Santo.Invalid{reasons: reasons}} = Registry.ingest("12345678")
      assert :unrecognized_shape in reasons
      assert Repo.aggregate(Vehicle, :count) == 0
    end
  end

  describe "list_vehicles/0" do
    test "returns all vehicles, most recently ingested first" do
      {:ok, first} = Registry.ingest(@cgt)
      {:ok, second} = Registry.ingest(@nine_five_nine)

      assert Enum.map(Registry.list_vehicles(), & &1.id) == [second.id, first.id]
    end
  end

  describe "fetch_vehicle/1" do
    test "fetches by id and rejects unknown or malformed ids" do
      {:ok, vehicle} = Registry.ingest(@cgt)

      assert {:ok, %Vehicle{id: id}} = Registry.fetch_vehicle(vehicle.id)
      assert id == vehicle.id
      assert {:error, :not_found} = Registry.fetch_vehicle(Ecto.UUID.generate())
      assert {:error, :not_found} = Registry.fetch_vehicle("not-a-uuid")
    end
  end
end
