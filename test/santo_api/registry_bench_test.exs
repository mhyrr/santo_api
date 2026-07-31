defmodule SantoApi.RegistryBenchTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, EvidenceRequest}

  @nine_three "WP0ZZZ99ZTS392124"

  defp upload_fixture(content \\ "receipt body") do
    path = Path.join(System.tmp_dir!(), "bench-upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  describe "create_upload_artifact/1" do
    test "copies the file into the uploads dir, hashed, and records the artifact" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      path = upload_fixture()

      {:ok, %Artifact{} = artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: path,
          filename: "invoice.pdf",
          mime: "application/pdf",
          kind: :receipt
        })

      assert artifact.kind == :receipt
      assert artifact.vehicle_id == vehicle.id
      assert artifact.mime == "application/pdf"
      assert artifact.metadata["filename"] == "invoice.pdf"
      assert artifact.storage_ref == artifact.sha256 <> ".pdf"

      stored = Path.join(Application.fetch_env!(:santo_api, :uploads_dir), artifact.storage_ref)
      assert File.read!(stored) == "receipt body"

      assert [%Artifact{id: id}] = Registry.list_artifacts(vehicle.id)
      assert id == artifact.id
    end

    test "carries source_url and merges caller metadata for provenance" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, %Artifact{} = artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture(),
          filename: "listing.html",
          mime: "text/html",
          kind: :listing,
          source_url: "https://example.com/listing/some-car/",
          metadata: %{"rights" => "manual corpus research, internal use"}
        })

      assert artifact.source_url == "https://example.com/listing/some-car/"
      assert artifact.metadata["rights"] == "manual corpus research, internal use"
      assert artifact.metadata["filename"] == "listing.html"
    end

    test "identical content dedupes to the same artifact" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, first} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("same bytes"),
          filename: "a.jpg",
          mime: "image/jpeg",
          kind: :photo
        })

      {:ok, second} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("same bytes"),
          filename: "b.jpg",
          mime: "image/jpeg",
          kind: :photo
        })

      assert first.id == second.id
      assert Repo.aggregate(Artifact, :count) == 1
    end
  end

  describe "propose_claim/2" do
    test "a human claim enters proposed with vocabulary scope, and observed stays out of facts" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, %Claim{} = claim} =
        Registry.propose_claim(vehicle, %{
          predicate: "observation.mileage",
          value: 43_210,
          scope_date: ~D[2026-07-30]
        })

      assert claim.state == :proposed
      assert claim.method == :human
      assert claim.scope_kind == :observed
      assert claim.scope_date == ~D[2026-07-30]

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      refute Map.has_key?(vehicle.facts, "observation.mileage")
    end

    test "rejects predicates and values outside the vocabulary" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      assert {:error, %Ecto.Changeset{}} =
               Registry.propose_claim(vehicle, %{predicate: "build.paint_code", value: "L041"})

      assert {:error, %Ecto.Changeset{}} =
               Registry.propose_claim(vehicle, %{predicate: "observation.mileage", value: "lots"})
    end

    test "an identical proposal is a changeset error, not a duplicate row" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      attrs = %{predicate: "observation.mileage", value: 1, scope_date: ~D[2026-07-30]}

      assert {:ok, _claim} = Registry.propose_claim(vehicle, attrs)
      assert {:error, %Ecto.Changeset{errors: errors}} = Registry.propose_claim(vehicle, attrs)
      assert Keyword.has_key?(errors, :content_hash)
    end
  end

  describe "ratify_claim/1 and reject_claim/1" do
    test "ratifying flips to admitted and the fact turns verified" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, claim} =
        Registry.propose_claim(vehicle, %{predicate: "build.variant", value: "coupe"})

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      assert vehicle.facts["build.variant"]["status"] == "unverified"

      {:ok, %Claim{state: :admitted}} = Registry.ratify_claim(claim.id)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      assert vehicle.facts["build.variant"] == %{"value" => "coupe", "status" => "verified"}
    end

    test "rejecting removes the claim from facts and comparison" do
      {:ok, vehicle} = Registry.ingest(@nine_three)

      {:ok, claim} =
        Registry.propose_claim(vehicle, %{predicate: "build.variant", value: "wrong"})

      {:ok, %Claim{state: :rejected}} = Registry.reject_claim(claim.id)

      {:ok, vehicle} = Registry.fetch_vehicle(vehicle.id)
      refute Map.has_key?(vehicle.facts, "build.variant")
      refute Enum.any?(Registry.claim_comparison(vehicle.id), &(&1.predicate == "build.variant"))
    end

    test "only proposed claims flip" do
      {:ok, vehicle} = Registry.ingest(@nine_three)
      [claim | _] = Registry.list_claims(vehicle.id)

      assert claim.state == :admitted
      assert {:error, {:not_proposed, :admitted}} = Registry.ratify_claim(claim.id)
      assert {:error, :not_found} = Registry.ratify_claim(Ecto.UUID.generate())
    end
  end

  describe "satisfy_evidence_request/2" do
    test "marks the request satisfied with its evidence" do
      {:ok, vehicle} = Registry.ingest("81192")
      [request] = Registry.list_evidence_requests(vehicle.id)

      {:ok, artifact} =
        Registry.create_upload_artifact(%{
          vehicle_id: vehicle.id,
          path: upload_fixture("kardex copy"),
          filename: "kardex.pdf",
          mime: "application/pdf",
          kind: :document
        })

      {:ok, %EvidenceRequest{} = satisfied} =
        Registry.satisfy_evidence_request(request.id, %{artifact_id: artifact.id})

      assert satisfied.status == :satisfied
      assert satisfied.satisfied_by_artifact_id == artifact.id

      assert {:error, :not_open} =
               Registry.satisfy_evidence_request(request.id, %{artifact_id: artifact.id})
    end
  end
end
