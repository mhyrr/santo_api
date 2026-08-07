defmodule SantoApi.RegistryOriginationTest do
  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.{Claim, Vehicle}

  @cayman_vin "WP0AB29827U782968"

  describe "originate/1" do
    test "mints a real registry row with an :asserted identity" do
      assert {:ok, %Vehicle{} = vehicle} = Registry.originate("a green Lexus")

      assert vehicle.identity_kind == :asserted
      assert "asserted:" <> id = vehicle.identity_key
      assert id != ""
      assert vehicle.input == "a green Lexus"
      assert vehicle.public_id
      assert vehicle.decode_snapshot == nil
      assert vehicle.santo_version == nil
      assert vehicle.facts == %{}
      assert Registry.list_claims(vehicle.id) == []
    end

    test "every origination is a new car — asserted identities never dedupe" do
      {:ok, first} = Registry.originate("a green Lexus")
      {:ok, second} = Registry.originate("a green Lexus")

      assert first.id != second.id
      assert first.identity_key != second.identity_key
    end
  end

  describe "resolve_asserted/2 — unoccupied VIN flips in place" do
    setup do
      {:ok, vehicle} = Registry.originate("2007 Porsche Cayman S, 41,000 miles")
      %{vehicle: vehicle}
    end

    test "acquires the identity without moving the row", %{vehicle: vehicle} do
      assert {:ok, %Vehicle{} = resolved} = Registry.resolve_asserted(vehicle, @cayman_vin)

      assert resolved.id == vehicle.id
      assert resolved.public_id == vehicle.public_id
      assert resolved.identity_kind == :vin
      assert resolved.identity_key == "vin:" <> @cayman_vin
      assert resolved.decode_snapshot
      assert resolved.santo_version
    end

    test "decode fires and its facts arrive :admitted", %{vehicle: vehicle} do
      {:ok, resolved} = Registry.resolve_asserted(vehicle, @cayman_vin)

      decode_claims =
        Enum.filter(Registry.list_claims(resolved.id), &(&1.method == :santo))

      assert decode_claims != []
      assert Enum.all?(decode_claims, &(&1.state == :admitted))
      assert %{"value" => 2007, "status" => "verified"} = resolved.facts["identity.model_year"]
    end

    test "the owner's prior claims survive and the decode audits them", %{vehicle: vehicle} do
      owner = Registry.ensure_party("probe-owner", :owner)

      {:ok, claim} =
        Registry.propose_claim(vehicle, owner, %{
          "predicate" => "identity.model_year",
          "value" => 2005
        })

      {:ok, _admitted} = Registry.ratify_claim(claim.id, owner)

      {:ok, resolved} = Registry.resolve_asserted(vehicle, @cayman_vin)

      # Both sources stay in the ledger; the disagreement is derived, not stored.
      assert %Claim{state: :admitted} = Repo.get(Claim, claim.id)
      assert %{"status" => "conflicted"} = resolved.facts["identity.model_year"]
    end
  end

  describe "resolve_asserted/2 — occupied VIN is reported, never refused silently" do
    test "returns the occupied row and leaves the asserted car untouched" do
      {:ok, occupied} = Registry.ingest(@cayman_vin)
      {:ok, vehicle} = Registry.originate("my cayman")

      assert {:error, {:occupied, %Vehicle{id: occupied_id}}} =
               Registry.resolve_asserted(vehicle, @cayman_vin)

      assert occupied_id == occupied.id

      {:ok, unchanged} = Registry.fetch_vehicle(vehicle.id)
      assert unchanged.identity_kind == :asserted
      assert unchanged.identity_key == vehicle.identity_key
    end
  end

  describe "resolve_asserted/2 — one-way, one-time" do
    test "a resolved car never resolves again" do
      {:ok, vehicle} = Registry.originate("my cayman")
      {:ok, resolved} = Registry.resolve_asserted(vehicle, @cayman_vin)

      assert {:error, :already_resolved} =
               Registry.resolve_asserted(resolved, "WP0AC2A97JS176473")
    end

    test "ingested cars are not resolvable either" do
      {:ok, vehicle} = Registry.ingest(@cayman_vin)
      assert {:error, :already_resolved} = Registry.resolve_asserted(vehicle, @cayman_vin)
    end

    test "an invalid VIN is refused before anything is touched" do
      {:ok, vehicle} = Registry.originate("mystery car")

      assert {:error, %Santo.Invalid{}} = Registry.resolve_asserted(vehicle, "NOT A VIN")

      {:ok, unchanged} = Registry.fetch_vehicle(vehicle.id)
      assert unchanged.identity_kind == :asserted
    end
  end
end
