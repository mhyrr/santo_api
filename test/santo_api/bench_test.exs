defmodule SantoApi.BenchTest do
  @moduledoc """
  The operator ratification queue as a derived read over the existing ledger.
  """

  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApi.Origination
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    owner = user_fixture(%{handle: unique_user_handle()})
    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)
    operator = operator_fixture()

    %{
      vehicle: vehicle,
      owner: owner,
      owner_scope: Scope.for_user(owner),
      owner_party: Owners.party(owner),
      operator_scope: Scope.for_user(operator)
    }
  end

  test "only unresolved owner factory claims enter the queue", ctx do
    eligible = owner_factory_claim(ctx, "build.paint_code", paint("226", "Linden Green"))

    assert {:ok, ordinary} =
             Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
               date: ~D[2026-08-10],
               claims: [
                 %{predicate: "event.note", value: %{"text" => "ordinary update"}},
                 %{predicate: "observation.mileage", value: 41_700}
               ]
             })

    assert Enum.all?(ordinary.claims, &(&1.state == :admitted))

    vendor = Registry.ensure_party("Queue test provider", :vendor)

    assert {:ok, _vendor_claim} =
             Registry.propose_claim(ctx.vehicle, vendor, %{
               predicate: "build.variant",
               value: "coupe"
             })

    already_resolved = owner_factory_claim(ctx, "build.plant", "Uusikaupunki")
    assert {:ok, _rejected} = Registry.reject_claim(already_resolved.id)

    assert {:ok, %{vehicle: asserted}} =
             Origination.originate_for(ctx.owner, %{
               sentence: "1987 Porsche 911",
               claims: [
                 %{predicate: "identity.model_year", value: 1987},
                 %{predicate: "identity.marque", value: "porsche"},
                 %{predicate: "identity.model", value: %{"code" => "911", "label" => "911"}}
               ]
             })

    asserted_identity =
      Registry.list_claims(asserted.id)
      |> Enum.filter(&String.starts_with?(&1.predicate, "identity."))

    assert Enum.all?(asserted_identity, &(&1.state == :admitted))

    assert {:ok, rows} = Bench.list_pending_ratifications(ctx.operator_scope)
    assert Enum.map(rows, & &1.claim.id) == [eligible.id]
    assert {:ok, 1} = Bench.pending_ratification_count(ctx.operator_scope)
  end

  test "queue rows carry the source entry, party, evidence, and live competition", ctx do
    assert {:ok, competitor} =
             Registry.propose_claim(ctx.vehicle, %{
               predicate: "build.paint_code",
               value: paint("59", "Slate Grey Metallic")
             })

    assert {:ok, _admitted} = Registry.ratify_claim(competitor.id)

    path = Path.join(System.tmp_dir!(), "ratification-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "owner build sheet")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, entry} =
             Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
               date: ~D[2026-08-11],
               claims: [
                 %{predicate: "event.note", value: %{"text" => "Found the build sheet"}},
                 %{predicate: "build.paint_code", value: paint("226", "Linden Green")}
               ],
               attachments: [
                 %{
                   path: path,
                   filename: "build-sheet.pdf",
                   mime: "application/pdf",
                   kind: :document
                 }
               ]
             })

    proposed = Enum.find(entry.claims, &(&1.predicate == "build.paint_code"))

    assert {:ok, [row]} = Bench.list_pending_ratifications(ctx.operator_scope)
    assert row.claim.id == proposed.id
    assert row.party.id == ctx.owner_party.id
    assert row.source_entry.entry_ref == entry.entry_ref
    assert Enum.any?(row.source_entry.claims, &(&1.predicate == "event.note"))
    assert [%{artifact: artifact, role: :entry_attachment}] = row.evidence
    assert artifact.source_party.id == ctx.owner_party.id
    assert Enum.any?(row.competing_claims, &(&1.claim_id == competitor.id))
  end

  test "authorized decisions reuse the ledger transition and stale repeats are inert", ctx do
    claim = owner_factory_claim(ctx, "provenance.delivery_date", "2007-04-12")
    original_hash = claim.content_hash
    original_entry_ref = claim.entry_ref

    path = Path.join(System.tmp_dir!(), "ratification-audit-#{claim.id}.pdf")
    File.write!(path, "delivery record")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, artifact} =
             Registry.create_upload_artifact(%{
               vehicle_id: ctx.vehicle.id,
               path: path,
               filename: "delivery-record.pdf",
               mime: "application/pdf",
               kind: :document,
               entry_ref: claim.entry_ref,
               source_party: ctx.owner_party
             })

    assert {:ok, admitted} = Bench.ratify_claim(ctx.operator_scope, claim.id)
    assert admitted.state == :admitted
    assert admitted.ratified_by_party_id == Registry.vin_santo_party().id
    assert admitted.ratified_at

    first_decided_at = admitted.ratified_at
    assert {:error, {:not_proposed, :admitted}} = Bench.ratify_claim(ctx.operator_scope, claim.id)

    unchanged = Repo.get!(Claim, claim.id)
    assert unchanged.ratified_at == first_decided_at
    assert unchanged.content_hash == original_hash
    assert unchanged.entry_ref == original_entry_ref
    assert unchanged.asserted_by_party_id == ctx.owner_party.id
    assert Enum.any?(Registry.list_claims(ctx.vehicle.id), &(&1.id == claim.id))
    assert Enum.any?(Registry.list_artifacts(ctx.vehicle.id), &(&1.id == artifact.id))
    assert Registry.list_adjudications(ctx.vehicle.id) == []

    {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
    assert vehicle.facts["provenance.delivery_date"]["status"] == "verified"
  end

  test "non-operators cannot read or resolve the queue", ctx do
    claim = owner_factory_claim(ctx, "build.plant", "Uusikaupunki")
    non_operator_scope = Scope.for_user(user_fixture())

    assert {:error, :not_authorized} = Bench.list_pending_ratifications(non_operator_scope)
    assert {:error, :not_authorized} = Bench.ratify_claim(non_operator_scope, claim.id)
    assert Repo.get!(Claim, claim.id).state == :proposed
  end

  defp owner_factory_claim(ctx, predicate, value) do
    assert {:ok, entry} =
             Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: predicate, value: value}]
             })

    assert [claim] = entry.claims
    claim
  end

  defp paint(code, label), do: %{"code" => code, "label" => label}
end
