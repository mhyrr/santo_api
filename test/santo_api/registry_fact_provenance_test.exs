defmodule SantoApi.RegistryFactProvenanceTest do
  @moduledoc """
  The public receipts beneath `vehicle.facts`.

  This is a privacy boundary as well as a read model: claims remain attributable,
  while private artifacts, possession proofs, and internal provider snapshots
  never cross it.
  """
  use SantoApi.DataCase, async: false

  alias SantoApi.Registry
  alias SantoApi.Registry.Artifact

  defp car do
    {:ok, vehicle} = Registry.register_chassis(:ferrari, :pre_vin, "04268")
    vehicle
  end

  defp reference(vehicle, party, url, attrs \\ %{}) do
    {:ok, artifact} =
      Registry.create_reference_artifact(
        vehicle,
        party,
        Map.merge(
          %{
            source_url: url,
            acquired_at: ~U[2026-08-04 12:00:00.000000Z],
            metadata: %{"rights_profile" => "public-pointer-only-v1"}
          },
          attrs
        )
      )

    artifact
  end

  defp propose(vehicle, party, artifact, predicate, value) do
    {:ok, claim} =
      Registry.propose_claim(
        vehicle,
        party,
        %{predicate: predicate, value: value, artifact_id: artifact.id},
        distinct_by_artifact: true
      )

    claim
  end

  test "keeps equivalent proposed claims separately attributable and dedupes their link" do
    vehicle = car()
    rm = Registry.ensure_party("RM Auctions", :vendor)
    bat = Registry.ensure_party("Bring a Trailer", :vendor)
    url = "https://example.com/1972-dino-246-gts"
    rm_artifact = reference(vehicle, rm, url)
    bat_artifact = reference(vehicle, bat, url)
    value = %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"}

    rm_claim = propose(vehicle, rm, rm_artifact, "identity.model", value)
    bat_claim = propose(vehicle, bat, bat_artifact, "identity.model", value)

    provenance = Registry.public_fact_provenance(vehicle.id)

    assert %{
             claims: claims,
             sources: [%{url: ^url, parties: ["Bring a Trailer", "RM Auctions"]}]
           } =
             provenance["identity.model"]

    assert Enum.map(claims, & &1.claim_id) |> Enum.sort() ==
             Enum.sort([rm_claim.id, bat_claim.id])

    assert Enum.map(claims, & &1.party) |> Enum.sort() ==
             ["Bring a Trailer", "RM Auctions"]

    assert Enum.all?(claims, &(&1.state == :proposed))
    assert Enum.all?(claims, &(&1.artifact.kind == :reference))
    assert Enum.all?(claims, &(&1.artifact.acquired_at == ~U[2026-08-04 12:00:00.000000Z]))
  end

  test "withholds private artifacts, provider snapshots, and possession proofs" do
    vehicle = car()
    source = Registry.ensure_party("Archive", :vendor)

    private = reference(vehicle, source, "https://private.example/factory-card")
    {:ok, private} = Registry.set_visibility(private, :private)

    snapshot =
      Repo.insert!(%Artifact{
        vehicle_id: vehicle.id,
        source_party_id: source.id,
        kind: :api_snapshot,
        acquisition_id: Ecto.UUID.generate(),
        sha256: String.duplicate("a", 64),
        source_url: "https://internal.example/provider-response",
        acquired_at: ~U[2026-08-04 12:01:00.000000Z],
        visibility: :public
      })

    proof =
      Repo.insert!(%Artifact{
        vehicle_id: vehicle.id,
        source_party_id: source.id,
        kind: :photo,
        sha256: String.duplicate("b", 64),
        source_url: "https://private.example/possession-proof",
        acquired_at: ~U[2026-08-04 12:02:00.000000Z],
        visibility: :public,
        metadata: %{"purpose" => "possession_proof"}
      })

    propose(vehicle, source, private, "identity.marque", "ferrari")
    propose(vehicle, source, snapshot, "identity.model_year", 1972)

    propose(
      vehicle,
      source,
      proof,
      "identity.model",
      %{"code" => "dino_246_gts", "label" => "Dino 246 GTS"}
    )

    provenance = Registry.public_fact_provenance(vehicle.id)

    assert Enum.all?(provenance, fn {_predicate, fact} -> fact.sources == [] end)

    assert Enum.all?(provenance, fn {_predicate, fact} ->
             Enum.all?(fact.claims, &is_nil(&1.artifact))
           end)
  end

  test "event claims never enter fact provenance, proposed or admitted" do
    vehicle = car()
    party = Registry.ensure_party("RM Auctions", :vendor)
    artifact = reference(vehicle, party, "https://example.com/sale")

    {:ok, proposed} =
      Registry.propose_claim(vehicle, party, %{
        predicate: "event.sale",
        value: %{"venue" => "RM Auctions", "price" => 352_000, "currency" => "USD"},
        scope_date: ~D[2014-01-17],
        artifact_id: artifact.id
      })

    assert Registry.public_fact_provenance(vehicle.id) == %{}

    {:ok, _admitted} = Registry.ratify_claim(proposed.id)
    assert Registry.public_fact_provenance(vehicle.id) == %{}
  end
end
