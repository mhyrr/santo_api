defmodule SantoApi.RegistryEvidenceTest do
  use SantoApi.DataCase, async: true

  alias SantoApi.Registry
  alias SantoApi.Registry.Artifact
  alias SantoApi.VpicFixtures

  @cgt "WP0CA298X5L001502"

  defp stub_vpic(response \\ VpicFixtures.cgt_response()) do
    Req.Test.stub(SantoApi.Vpic, fn conn -> Req.Test.json(conn, response) end)
  end

  describe "ingest_vpic/1" do
    test "stores the snapshot artifact and proposed structured_api claims" do
      stub_vpic()
      {:ok, vehicle} = Registry.ingest(@cgt)

      assert {:ok, %Artifact{} = artifact} = Registry.ingest_vpic(vehicle)

      assert artifact.kind == :api_snapshot
      assert is_binary(artifact.sha256)
      assert artifact.payload["Model"] == "911"
      assert artifact.source_url =~ "DecodeVinValues"
      assert %DateTime{} = artifact.acquired_at

      vpic_party = Registry.ensure_party("NHTSA vPIC", :vendor)

      vpic_claims =
        Registry.list_claims(vehicle.id)
        |> Enum.filter(&(&1.method == :structured_api))

      assert length(vpic_claims) == 3

      for claim <- vpic_claims do
        assert claim.state == :proposed
        assert claim.artifact_id == artifact.id
        assert claim.asserted_by_party_id == vpic_party.id
      end

      model_claim = Enum.find(vpic_claims, &(&1.predicate == "identity.model"))
      assert model_claim.value == %{"code" => "911", "label" => nil}
    end

    test "re-running the lookup duplicates nothing" do
      stub_vpic()
      {:ok, vehicle} = Registry.ingest(@cgt)

      {:ok, first} = Registry.ingest_vpic(vehicle)
      {:ok, second} = Registry.ingest_vpic(vehicle)

      assert first.id == second.id
      assert Repo.aggregate(Artifact, :count) == 1
      assert length(Registry.list_claims(vehicle.id)) == 5 + 3
    end

    test "non-VIN identities are outside vPIC scope" do
      {:ok, disputed} = Registry.ingest("81192")

      assert {:error, :unsupported_identity} = Registry.ingest_vpic(disputed)
      assert Repo.aggregate(Artifact, :count) == 0
    end

    test "a vPIC failure stores nothing" do
      Req.Test.stub(SantoApi.Vpic, fn conn -> Plug.Conn.send_resp(conn, 500, "down") end)
      {:ok, vehicle} = Registry.ingest(@cgt)

      assert {:error, _} = Registry.ingest_vpic(vehicle)
      assert Repo.aggregate(Artifact, :count) == 0
    end
  end

  describe "claim_comparison/1" do
    test "labels agreement, conflict, and single-source per predicate, oracle-style" do
      stub_vpic()
      {:ok, vehicle} = Registry.ingest(@cgt)
      {:ok, _artifact} = Registry.ingest_vpic(vehicle)

      comparison = Registry.claim_comparison(vehicle.id)
      by_predicate = Map.new(comparison, &{&1.predicate, &1})

      assert by_predicate["identity.marque"].status == :agreement
      assert by_predicate["identity.model_year"].status == :agreement
      assert by_predicate["identity.model"].status == :conflict
      assert by_predicate["build.plant"].status == :single_source
      assert by_predicate["identity.market"].status == :single_source

      model = by_predicate["identity.model"]
      parties = Enum.map(model.claims, & &1.party) |> Enum.sort()
      assert parties == ["NHTSA vPIC", "Vin Santo"]

      santo_entry = Enum.find(model.claims, &(&1.party == "Vin Santo"))
      assert santo_entry.value["code"] == "carrera_gt"
      assert santo_entry.state == :admitted
    end

    test "equivalence ignores the model label, comparing codes only" do
      stub_vpic(VpicFixtures.response(%{VpicFixtures.cgt_values() | "Model" => "Carrera GT"}))
      {:ok, vehicle} = Registry.ingest(@cgt)
      {:ok, _artifact} = Registry.ingest_vpic(vehicle)

      comparison = Registry.claim_comparison(vehicle.id)
      model = Enum.find(comparison, &(&1.predicate == "identity.model"))

      assert model.status == :agreement
    end
  end
end
