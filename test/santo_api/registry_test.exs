defmodule SantoApi.RegistryTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, EvidenceRequest, Vehicle}

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

    test "mints a public_id — the canonical URL keys the row, not the VIN" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      assert String.length(vehicle.public_id) == 10
      assert vehicle.public_id =~ ~r/\A[a-z2-7]{10}\z/
    end

    test "the public_id survives re-ingest — a shared link must not rot" do
      {:ok, first} = Registry.ingest(@nine_five_nine)
      {:ok, again} = Registry.ingest(@nine_five_nine)

      assert again.public_id == first.public_id
    end

    test "distinct cars get distinct public_ids" do
      {:ok, one} = Registry.ingest(@nine_five_nine)
      {:ok, two} = Registry.ingest(@cgt)

      refute one.public_id == two.public_id
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

  describe "register_chassis/3" do
    test "registers a trusted Ferrari chassis outside Santo's current adapters" do
      assert {:ok, %Vehicle{} = vehicle} =
               Registry.register_chassis(:ferrari, :pre_vin, " 00548 ")

      assert vehicle.identity_kind == :chassis
      assert vehicle.identity_key == "chassis:ferrari:pre_vin:00548"
      assert vehicle.input == "00548"
      assert is_nil(vehicle.decode_snapshot)
      assert is_nil(vehicle.santo_version)
      assert Registry.list_claims(vehicle.id) == []
    end

    test "stores a pointer without pretending the referenced page was copied" do
      {:ok, vehicle} = Registry.register_chassis(:ferrari, :pre_vin, "00548")
      source = Registry.ensure_party("Bring a Trailer", :vendor)

      attrs = %{
        source_url: "https://bringatrailer.com/listing/1969-ferrari-dino/",
        metadata: %{"rights_profile" => "public-pointer-only-v1"}
      }

      assert {:ok, %Artifact{} = first} =
               Registry.create_reference_artifact(vehicle, source, attrs)

      assert {:ok, %Artifact{} = second} =
               Registry.create_reference_artifact(vehicle, source, attrs)

      assert first.id == second.id
      assert first.kind == :reference
      assert is_nil(first.payload)
      assert is_nil(first.storage_ref)
      assert first.source_url == attrs.source_url
    end
  end

  describe "register_vin/2" do
    test "registers a reviewed Ferrari VIN without inventing decode claims" do
      assert {:ok, %Vehicle{} = vehicle} =
               Registry.register_vin(:ferrari, " zff75vfa8f0205055 ")

      assert vehicle.identity_kind == :vin
      assert vehicle.identity_key == "vin:ZFF75VFA8F0205055"
      assert vehicle.input == "ZFF75VFA8F0205055"
      assert is_nil(vehicle.decode_snapshot)
      assert is_nil(vehicle.santo_version)
      assert Registry.list_claims(vehicle.id) == []
    end

    test "rejects unreviewed marques and non-Ferrari VINs" do
      assert {:error, :invalid_vin_identity} =
               Registry.register_vin(:porsche, "WP0CA298X5L001256")

      assert {:error, :invalid_vin_identity} =
               Registry.register_vin(:ferrari, "WP0CA298X5L001256")
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

  describe "fetch_by_public_id/1" do
    test "resolves the canonical public identifier" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      assert {:ok, found} = Registry.fetch_by_public_id(vehicle.public_id)
      assert found.id == vehicle.id
    end

    test "is case-insensitive, so a link typed in caps still lands" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      assert {:ok, found} = Registry.fetch_by_public_id(String.upcase(vehicle.public_id))
      assert found.id == vehicle.id
    end

    test "rejects unknown and malformed ids without touching the database twice" do
      assert {:error, :not_found} = Registry.fetch_by_public_id("aaaaaaaaaa")
      assert {:error, :not_found} = Registry.fetch_by_public_id("nope")
      assert {:error, :not_found} = Registry.fetch_by_public_id(nil)
    end
  end

  describe "resolve_vin/1" do
    test "finds an existing car by VIN so /vin/:vin can redirect to canonical" do
      {:ok, vehicle} = Registry.ingest(@nine_five_nine)

      assert {:ok, found} = Registry.resolve_vin(" wp0zzz95zjs905016 ")
      assert found.public_id == vehicle.public_id
    end

    test "does not create a car as a side effect of looking one up" do
      assert {:error, :not_found} = Registry.resolve_vin(@cgt)
      assert Registry.list_vehicles() == []
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
