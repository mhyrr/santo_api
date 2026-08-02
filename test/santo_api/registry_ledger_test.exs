defmodule SantoApi.RegistryLedgerTest do
  @moduledoc """
  The ledger prerequisites the owner surface needs (TK-008): ratification
  attribution, entry grouping, artifact sourcing, and presentation visibility.
  """
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.Claim

  @nine_three "WP0ZZZ99ZTS392124"

  defp proposal(vehicle, attrs \\ %{predicate: "build.variant", value: "coupe"}) do
    {:ok, claim} = Registry.propose_claim(vehicle, attrs)
    claim
  end

  describe "ratification attribution" do
    test "ratify_claim/1 stamps Vin Santo and the moment of the flip" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      claim = proposal(vehicle)

      assert is_nil(claim.ratified_by_party_id)
      assert is_nil(claim.ratified_at)

      {:ok, admitted} = Registry.ratify_claim(claim.id)

      assert admitted.state == :admitted
      assert admitted.ratified_by_party_id == Registry.vin_santo_party().id
      assert DateTime.after?(admitted.ratified_at, claim.inserted_at)
    end

    test "ratify_claim/2 stamps the supplied party — the owner self-ratification path" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("Jean Behra", :owner)
      claim = proposal(vehicle, %{predicate: "observation.mileage", value: 12_000})

      {:ok, admitted} = Registry.ratify_claim(claim.id, owner)

      assert admitted.ratified_by_party_id == owner.id
      refute admitted.ratified_by_party_id == Registry.vin_santo_party().id
    end

    test "reject_claim records its decider the same way" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      operator = Registry.ensure_party("Bench Operator", :registry)
      claim = proposal(vehicle, %{predicate: "build.variant", value: "wrong"})

      {:ok, rejected} = Registry.reject_claim(claim.id, operator)

      assert rejected.state == :rejected
      assert rejected.ratified_by_party_id == operator.id
      assert rejected.ratified_at
    end

    test "santo-emitted claims carry no ratifier — they never passed through the gate" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      santo_claims =
        vehicle.id |> Registry.list_claims() |> Enum.filter(&(&1.method == :santo))

      assert santo_claims != []

      for %Claim{} = claim <- santo_claims do
        assert claim.state == :admitted
        assert is_nil(claim.ratified_by_party_id)
        assert is_nil(claim.ratified_at)
      end
    end
  end

  describe "entry_ref" do
    @fill_up %{
      predicate: "event.fuel",
      value: %{"volume" => "10.0", "unit" => "gal"},
      scope_date: ~D[2026-07-30]
    }

    test "new_entry_ref/0 mints a time-ordered v7 uuid" do
      a = Registry.new_entry_ref()
      b = Registry.new_entry_ref()

      assert {:ok, <<_::48, 7::4, _::12, 2::2, _::62>>} = Ecto.UUID.dump(a)
      assert a != b
    end

    test "two identical events under different entries are two claims" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, first} =
        Registry.propose_claim(vehicle, Map.put(@fill_up, :entry_ref, Registry.new_entry_ref()))

      {:ok, second} =
        Registry.propose_claim(vehicle, Map.put(@fill_up, :entry_ref, Registry.new_entry_ref()))

      assert first.entry_ref != second.entry_ref
      assert first.content_hash != second.content_hash
      assert first.id != second.id
    end

    test "the same event twice under one entry still dedupes" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      attrs = Map.put(@fill_up, :entry_ref, Registry.new_entry_ref())

      assert {:ok, _claim} = Registry.propose_claim(vehicle, attrs)
      assert {:error, %Ecto.Changeset{errors: errors}} = Registry.propose_claim(vehicle, attrs)
      assert Keyword.has_key?(errors, :content_hash)
    end

    test "an event claim with no entry_ref hashes exactly as it always did" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      {:ok, claim} = Registry.propose_claim(vehicle, @fill_up)

      assert is_nil(claim.entry_ref)

      assert claim.content_hash ==
               Claim.hash(
                 vehicle.identity_key,
                 @fill_up.predicate,
                 @fill_up.value,
                 :event,
                 @fill_up.scope_date,
                 :human,
                 "Vin Santo"
               )
    end

    test "factory and observed hashing is untouched by entry_ref" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      bare = %{predicate: "build.variant", value: "coupe"}

      {:ok, claim} =
        Registry.propose_claim(vehicle, Map.put(bare, :entry_ref, Registry.new_entry_ref()))

      assert claim.entry_ref
      assert {:error, %Ecto.Changeset{errors: errors}} = Registry.propose_claim(vehicle, bare)
      assert Keyword.has_key?(errors, :content_hash)
    end

    test "artifacts carry the entry_ref so a multi-photo entry hangs together" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      entry_ref = Registry.new_entry_ref()

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("a photo"),
          filename: "wheels.jpg",
          mime: "image/jpeg",
          kind: :photo,
          entry_ref: entry_ref
        })

      assert artifact.entry_ref == entry_ref
    end
  end

  describe "upload sourcing" do
    test "an upload records the party that supplied it" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      owner = Registry.ensure_party("Jean Behra", :owner)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("owner's invoice"),
          filename: "invoice.pdf",
          mime: "application/pdf",
          kind: :receipt,
          source_party: owner
        })

      assert artifact.source_party_id == owner.id
    end

    test "an upload with no supplying party falls back to Vin Santo — the bench path" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("bench scan"),
          filename: "kardex.pdf",
          mime: "application/pdf",
          kind: :document
        })

      assert artifact.source_party_id == Registry.vin_santo_party().id
    end
  end

  describe "visibility" do
    test "claims and artifacts are public by default" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      claim = proposal(vehicle)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("photo bytes"),
          filename: "front.jpg",
          mime: "image/jpeg",
          kind: :photo
        })

      assert claim.visibility == :public
      assert artifact.visibility == :public
    end

    test "flipping a claim's visibility touches neither its hash nor its state" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      claim = proposal(vehicle)
      {:ok, claim} = Registry.ratify_claim(claim.id)

      {:ok, hidden} = Registry.set_visibility(claim, :private)

      assert hidden.visibility == :private
      assert hidden.content_hash == claim.content_hash
      assert hidden.state == :admitted
    end

    test "flipping an artifact's visibility leaves the acquired thing alone" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("title document"),
          filename: "title.pdf",
          mime: "application/pdf",
          kind: :document
        })

      {:ok, hidden} = Registry.set_visibility(artifact, :private)

      assert hidden.visibility == :private
      assert hidden.sha256 == artifact.sha256
      assert hidden.storage_ref == artifact.storage_ref
    end
  end

  defp upload_fixture(content) do
    path = Path.join(System.tmp_dir!(), "ledger-upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end
end
