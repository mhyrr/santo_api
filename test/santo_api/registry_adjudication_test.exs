defmodule SantoApi.RegistryAdjudicationTest do
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.{Adjudication, Claim, EvidenceRequest}
  alias SantoApi.VpicFixtures

  @cayman "WP0AB29827U782968"
  @carrera_gt "WP0CA298X5L001256"
  @corpus_dir Path.expand("../../priv/corpus", __DIR__)

  describe "adjudicate_claims/4" do
    test "corrects the Cayman fact while preserving santo's claim in history" do
      stub_vpic(VpicFixtures.cayman_response())
      {:ok, vehicle} = Registry.ingest(@cayman)
      {:ok, _snapshot} = Registry.ingest_vpic(vehicle)

      santo_claim = claim!(vehicle, "identity.model", :santo)
      vpic_claim = claim!(vehicle, "identity.model", :structured_api)
      coa = upload!(vehicle, "cayman_s/porsche_coa.jpg", :document)

      assert {:ok, %Adjudication{} = adjudication} =
               Registry.adjudicate_claims(
                 Registry.vin_santo_party(),
                 santo_claim.id,
                 vpic_claim.id,
                 %{
                   outcome: :supersede,
                   prevailing_claim_id: vpic_claim.id,
                   evidence_artifact_ids: [coa.id],
                   note: "The Porsche CoA identifies this VIN as a Cayman S."
                 }
               )

      assert adjudication.outcome == :supersede
      assert adjudication.prevailing_claim_id == vpic_claim.id
      assert adjudication.evidence_artifact_ids == [coa.id]

      assert %Claim{state: :superseded, value: %{"code" => "boxster"}} =
               fetch_claim!(santo_claim.id)

      assert %Claim{state: :admitted, value: %{"code" => "cayman"}} =
               fetch_claim!(vpic_claim.id)

      {:ok, corrected} = Registry.fetch_vehicle(vehicle.id)

      assert corrected.facts["identity.model"] == %{
               "value" => %{"code" => "cayman", "label" => nil},
               "status" => "verified"
             }

      assert comparison!(vehicle, "identity.model").claims |> length() == 1
      assert Enum.any?(Registry.list_claims(vehicle.id), &(&1.state == :superseded))
    end

    test "adjudicates the Carrera GT mirror direction" do
      response =
        VpicFixtures.cgt_values() |> Map.put("VIN", @carrera_gt) |> VpicFixtures.response()

      stub_vpic(response)
      {:ok, vehicle} = Registry.ingest(@carrera_gt)
      {:ok, _snapshot} = Registry.ingest_vpic(vehicle)

      santo_claim = claim!(vehicle, "identity.model", :santo)
      vpic_claim = claim!(vehicle, "identity.model", :structured_api)
      sticker = upload!(vehicle, "carrera_gt/window_sticker.jpg", :document)

      assert {:ok, %Adjudication{outcome: :supersede}} =
               Registry.adjudicate_claims(
                 Registry.vin_santo_party(),
                 santo_claim.id,
                 vpic_claim.id,
                 %{
                   outcome: :supersede,
                   prevailing_claim_id: santo_claim.id,
                   evidence_artifact_ids: [sticker.id],
                   note: "The original window sticker identifies the Carrera GT."
                 }
               )

      assert %Claim{state: :admitted, value: %{"code" => "carrera_gt"}} =
               fetch_claim!(santo_claim.id)

      assert %Claim{state: :superseded, value: %{"code" => "911"}} =
               fetch_claim!(vpic_claim.id)

      {:ok, corrected} = Registry.fetch_vehicle(vehicle.id)
      assert corrected.facts["identity.model"]["value"]["code"] == "carrera_gt"
      assert corrected.facts["identity.model"]["status"] == "verified"
    end

    test "coexists with a note and requests evidence as append-only casebook outcomes" do
      {:ok, vehicle} = Registry.ingest(@carrera_gt)
      porsche = Registry.ensure_party("Porsche AG", :vendor)
      operator = Registry.vin_santo_party()
      sticker = upload!(vehicle, "carrera_gt/window_sticker.jpg", :document)

      {:ok, first} =
        Registry.propose_claim(vehicle, porsche, %{
          predicate: "build.variant",
          value: "Carrera GT"
        })

      {:ok, second} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.variant",
          value: "980"
        })

      assert first.asserted_by_party_id == porsche.id

      assert {:ok, %Adjudication{outcome: :coexist_with_note} = coexist} =
               Registry.adjudicate_claims(operator, first.id, second.id, %{
                 outcome: :coexist_with_note,
                 evidence_artifact_ids: [sticker.id],
                 note: "Marketing name and internal platform designation both belong in history."
               })

      assert fetch_claim!(first.id).state == :admitted
      assert fetch_claim!(second.id).state == :admitted

      assert_raise Postgrex.Error, ~r/append-only/, fn ->
        Repo.transaction(
          fn -> coexist |> Ecto.Changeset.change(note: "rewritten") |> Repo.update!() end,
          mode: :savepoint
        )
      end

      {:ok, third} =
        Registry.propose_claim(vehicle, porsche, %{
          predicate: "build.paint_code",
          value: %{"code" => "1C1", "label" => "Fayence Yellow"}
        })

      {:ok, fourth} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.paint_code",
          value: %{"code" => "M1C", "label" => "Fayence Yellow"}
        })

      assert {:ok,
              %Adjudication{
                outcome: :request_evidence,
                evidence_request_id: request_id
              }} =
               Registry.adjudicate_claims(operator, third.id, fourth.id, %{
                 outcome: :request_evidence,
                 requested_evidence_classes: ["coa", "window_sticker"],
                 note: "The label agrees but the codes do not."
               })

      assert %EvidenceRequest{status: :open, subject: "build.paint_code"} =
               Repo.get!(EvidenceRequest, request_id)
    end
  end

  describe "artifact-independent comparison and fact precedence" do
    test "the Cayman CoA and window sticker paint claims agree despite a shared party" do
      {:ok, vehicle} = Registry.ingest(@cayman)
      coa = upload!(vehicle, "cayman_s/porsche_coa.jpg", :document)
      sticker = upload!(vehicle, "cayman_s/window_sticker_1.jpg", :document)

      {:ok, coa_claim} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.paint_code",
          value: %{"code" => "59", "label" => "Slate Grey Metallic"},
          artifact_id: coa.id
        })

      {:ok, sticker_claim} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.paint_code",
          value: %{"code" => nil, "label" => "Slate Grey Metallic"},
          artifact_id: sticker.id
        })

      {:ok, _} = Registry.ratify_claim(coa_claim.id)
      {:ok, _} = Registry.ratify_claim(sticker_claim.id)

      comparison = comparison!(vehicle, "build.paint_code")
      assert comparison.status == :agreement
      assert Enum.map(comparison.claims, & &1.party) |> Enum.uniq() == ["Vin Santo"]
      assert Enum.map(comparison.claims, & &1.artifact_id) |> Enum.uniq() |> length() == 2
    end

    test "artifact independence does not turn observations at different dates into conflict" do
      {:ok, vehicle} = Registry.ingest(@carrera_gt)
      invoice = upload!(vehicle, "carrera_gt/service_invoice_p3.jpg", :receipt)
      listing = upload!(vehicle, "carrera_gt/listing_page.html", :listing)

      {:ok, earlier} =
        Registry.propose_claim(vehicle, %{
          predicate: "observation.mileage",
          value: 8_803,
          scope_date: ~D[2024-10-24],
          artifact_id: invoice.id
        })

      {:ok, later} =
        Registry.propose_claim(vehicle, %{
          predicate: "observation.mileage",
          value: 9_200,
          scope_date: ~D[2026-07-22],
          artifact_id: listing.id
        })

      {:ok, _} = Registry.ratify_claim(earlier.id)
      {:ok, _} = Registry.ratify_claim(later.id)

      assert comparison!(vehicle, "observation.mileage").status == :history
    end

    test "facts prefer the richest equivalent value instead of arrival order" do
      {:ok, vehicle} = Registry.ingest(@carrera_gt)
      sticker = upload!(vehicle, "carrera_gt/window_sticker.jpg", :document)
      listing = upload!(vehicle, "carrera_gt/listing_page.html", :listing)

      {:ok, label_only} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.paint_code",
          value: %{"code" => nil, "label" => "Fayence Yellow"},
          artifact_id: sticker.id
        })

      {:ok, richer} =
        Registry.propose_claim(vehicle, %{
          predicate: "build.paint_code",
          value: %{"code" => "1C1", "label" => "Fayence Yellow"},
          artifact_id: listing.id
        })

      {:ok, _} = Registry.ratify_claim(label_only.id)
      {:ok, _} = Registry.ratify_claim(richer.id)

      {:ok, refreshed} = Registry.fetch_vehicle(vehicle.id)

      assert refreshed.facts["build.paint_code"] == %{
               "value" => %{"code" => "1C1", "label" => "Fayence Yellow"},
               "status" => "verified"
             }
    end
  end

  defp stub_vpic(response) do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, response) end)
  end

  defp claim!(vehicle, predicate, method) do
    vehicle.id
    |> Registry.list_claims()
    |> Enum.find(&(&1.predicate == predicate and &1.method == method))
  end

  defp fetch_claim!(id), do: Repo.get!(Claim, id)

  defp comparison!(vehicle, predicate) do
    vehicle.id
    |> Registry.claim_comparison()
    |> Enum.find(&(&1.predicate == predicate))
  end

  defp upload!(vehicle, relative_path, kind) do
    path = Path.join(@corpus_dir, relative_path)

    {:ok, artifact} =
      Registry.create_upload_artifact(%{
        vehicle_id: vehicle.id,
        path: path,
        filename: Path.basename(path),
        mime: if(Path.extname(path) == ".html", do: "text/html", else: "image/jpeg"),
        kind: kind
      })

    artifact
  end
end
