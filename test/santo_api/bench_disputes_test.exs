defmodule SantoApi.BenchDisputesTest do
  @moduledoc """
  Contested possession is an authorization dispute, not a Registry claim pair.
  """

  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApi.Owners
  alias SantoApi.Owners.{Challenge, Stewardship}
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo

  setup do
    operator = operator_fixture()
    incumbent = user_fixture(%{handle: unique_user_handle()})
    claimant = user_fixture(%{handle: unique_user_handle()})
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")

    {:ok, incumbent_stewardship} = claim_and_approve(incumbent, vehicle, operator)
    {:ok, contested} = submit_claim(claimant, vehicle)

    %{
      operator: operator,
      operator_scope: Scope.for_user(operator),
      incumbent: incumbent,
      incumbent_stewardship: incumbent_stewardship,
      claimant: claimant,
      contested: contested,
      vehicle: vehicle
    }
  end

  test "the dispute queue contains only submitted claims facing another active steward", ctx do
    {:ok, other_vehicle} = Registry.ingest("WP0CA298X5L001256")
    ordinary_claimant = user_fixture(%{handle: unique_user_handle()})
    {:ok, ordinary} = submit_claim(ordinary_claimant, other_vehicle)

    assert {:ok, [row]} = Bench.list_pending_disputes(ctx.operator_scope)
    assert row.challenge.id == ctx.contested.id
    assert row.challenge.user.id == ctx.claimant.id
    assert row.incumbent.id == ctx.incumbent_stewardship.id
    assert row.incumbent.user.id == ctx.incumbent.id
    assert row.challenge.proof_artifact.id
    assert row.incumbent.proof_artifact.id
    assert {:ok, 1} = Bench.pending_dispute_count(ctx.operator_scope)

    ordinary_queue = Owners.list_pending_claiming_challenges()
    assert Enum.map(ordinary_queue, & &1.id) == [ordinary.id]
    refute Enum.any?(ordinary_queue, &(&1.id == ctx.contested.id))
  end

  test "keeping the incumbent denies the challenge and retains both evidence trails", ctx do
    claimant_proof_id = ctx.contested.proof_artifact_id
    incumbent_proof_id = ctx.incumbent_stewardship.proof_artifact_id

    assert {:ok, resolution} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :keep_incumbent,
               "The incumbent registration and continuous service record are stronger."
             )

    assert resolution.outcome == :keep_incumbent

    denied = Repo.get!(Challenge, ctx.contested.id)
    assert denied.status == :denied

    assert denied.reason ==
             "The incumbent registration and continuous service record are stronger."

    assert denied.decided_by_user_id == ctx.operator.id
    assert denied.decided_at

    incumbent = Repo.get!(Stewardship, ctx.incumbent_stewardship.id)
    assert incumbent.status == :active
    assert Owners.steward(ctx.vehicle).name == ctx.incumbent.handle

    artifact_ids = Registry.list_artifacts(ctx.vehicle.id) |> Enum.map(& &1.id)
    assert claimant_proof_id in artifact_ids
    assert incumbent_proof_id in artifact_ids
    assert {:ok, []} = Bench.list_pending_disputes(ctx.operator_scope)
  end

  test "transferring stewardship is atomic, attributable, and leaves prior entries intact", ctx do
    incumbent_scope = Scope.for_user(ctx.incumbent)
    claimant_scope = Scope.for_user(ctx.claimant)
    incumbent_party = Owners.party(ctx.incumbent)

    assert {:ok, entry} =
             Owners.compose_entry(incumbent_scope, ctx.vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "Incumbent history"}}]
             })

    [entry_claim] = entry.claims

    assert {:ok, resolution} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :transfer_to_claimant,
               "The claimant supplied the current registration and transfer bill."
             )

    assert resolution.outcome == :transfer_to_claimant

    revoked = Repo.get!(Stewardship, ctx.incumbent_stewardship.id)
    assert revoked.status == :revoked
    assert revoked.reason == "The claimant supplied the current registration and transfer bill."
    assert revoked.decided_by_user_id == ctx.operator.id
    assert revoked.decided_at

    approved = Repo.get!(Challenge, ctx.contested.id)
    assert approved.status == :approved
    assert approved.reason == "The claimant supplied the current registration and transfer bill."
    assert approved.decided_by_user_id == ctx.operator.id
    assert approved.decided_at

    granted = Repo.get_by!(Stewardship, vehicle_id: ctx.vehicle.id, status: :active)
    assert granted.user_id == ctx.claimant.id
    assert granted.proof_artifact_id == ctx.contested.proof_artifact_id
    assert granted.decided_by_user_id == ctx.operator.id
    assert Owners.steward(ctx.vehicle).name == ctx.claimant.handle

    assert {:error, :not_stewarded} =
             Owners.compose_entry(incumbent_scope, ctx.vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "No longer authorized"}}]
             })

    assert {:ok, _new_entry} =
             Owners.compose_entry(claimant_scope, ctx.vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "New steward update"}}]
             })

    retained = Repo.get!(Claim, entry_claim.id)
    assert retained.asserted_by_party_id == incumbent_party.id
    assert retained.state == :admitted
    assert retained.entry_ref == entry.entry_ref
  end

  test "stale and repeated decisions cannot create duplicate stewardship", ctx do
    assert {:ok, first} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :transfer_to_claimant,
               "Current registration names the claimant."
             )

    decided_at = first.challenge.decided_at

    assert {:error, {:not_pending, :approved}} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :keep_incumbent,
               "Try to overwrite the decision."
             )

    assert Repo.get!(Challenge, ctx.contested.id).decided_at == decided_at

    vehicle_stewardships =
      Repo.all(Stewardship)
      |> Enum.filter(&(&1.vehicle_id == ctx.vehicle.id))

    assert Enum.count(vehicle_stewardships, &(&1.status == :active)) == 1
    assert length(vehicle_stewardships) == 2
  end

  test "concurrent opposite decisions serialize on the challenge row", ctx do
    decisions = [
      {:keep_incumbent, "The incumbent evidence prevails."},
      {:transfer_to_claimant, "The claimant evidence prevails."}
    ]

    results =
      decisions
      |> Task.async_stream(
        fn {outcome, reason} ->
          Bench.resolve_dispute(ctx.operator_scope, ctx.contested.id, outcome, reason)
        end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _resolution}, &1)) == 1
    assert Enum.count(results, &match?({:error, {:not_pending, _state}}, &1)) == 1

    decided = Repo.get!(Challenge, ctx.contested.id)
    assert decided.status in [:approved, :denied]
    assert decided.decided_by_user_id == ctx.operator.id

    active =
      Repo.all(Stewardship)
      |> Enum.filter(&(&1.vehicle_id == ctx.vehicle.id and &1.status == :active))

    assert length(active) == 1
  end

  test "resolving one dispute does not touch another vehicle", ctx do
    other_incumbent = user_fixture(%{handle: unique_user_handle()})
    other_claimant = user_fixture(%{handle: unique_user_handle()})
    {:ok, other_vehicle} = Registry.ingest("WP0AC2A97JS176473")
    {:ok, other_stewardship} = claim_and_approve(other_incumbent, other_vehicle, ctx.operator)
    {:ok, other_dispute} = submit_claim(other_claimant, other_vehicle)

    assert {:ok, _resolution} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :keep_incumbent,
               "The incumbent evidence prevails."
             )

    assert Repo.get!(Challenge, other_dispute.id).status == :submitted
    assert Repo.get!(Stewardship, other_stewardship.id).status == :active
    assert Owners.steward(other_vehicle).name == other_incumbent.handle

    assert {:ok, [remaining]} = Bench.list_pending_disputes(ctx.operator_scope)
    assert remaining.challenge.id == other_dispute.id
  end

  test "the dispute boundary rejects missing reasons, invalid outcomes, and non-operators", ctx do
    non_operator_scope = Scope.for_user(user_fixture())

    assert {:error, :reason_required} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :keep_incumbent,
               "  "
             )

    assert {:error, :invalid_dispute_decision} =
             Bench.resolve_dispute(ctx.operator_scope, ctx.contested.id, :erase_history, "No")

    assert {:error, :not_authorized} = Bench.list_pending_disputes(non_operator_scope)

    assert {:error, :not_authorized} =
             Bench.resolve_dispute(
               non_operator_scope,
               ctx.contested.id,
               :keep_incumbent,
               "No authority"
             )

    assert Repo.get!(Challenge, ctx.contested.id).status == :submitted
    assert Repo.get!(Stewardship, ctx.incumbent_stewardship.id).status == :active
  end

  test "a dispute that lost its incumbent fails stale without deciding the claimant", ctx do
    assert {:ok, _revoked} =
             Owners.revoke_stewardship(
               ctx.incumbent_stewardship,
               "External revocation",
               ctx.operator
             )

    assert {:error, :not_contested} =
             Bench.resolve_dispute(
               ctx.operator_scope,
               ctx.contested.id,
               :transfer_to_claimant,
               "Stale page"
             )

    assert Repo.get!(Challenge, ctx.contested.id).status == :submitted
    refute Repo.get_by(Stewardship, user_id: ctx.claimant.id, status: :active)
  end

  defp claim_and_approve(user, vehicle, operator) do
    with {:ok, submitted} <- submit_claim(user, vehicle) do
      Owners.approve_challenge(submitted, operator)
    end
  end

  defp submit_claim(user, vehicle) do
    with {:ok, challenge} <- Owners.issue_challenge(user, vehicle) do
      Owners.submit_proof(challenge, photo())
    end
  end

  defp photo do
    path = Path.join(System.tmp_dir!(), "dispute-proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "VIN plate and challenge #{System.unique_integer([:positive])}")
    %{path: path, filename: Path.basename(path), mime: "image/jpeg"}
  end
end
