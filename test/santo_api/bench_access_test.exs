defmodule SantoApi.BenchAccessTest do
  @moduledoc """
  Operator access controls have deliberately different blast radii: account
  suspension gates credentials, while stewardship revocation gates one car.
  """

  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.{AccessDecision, Scope, User}
  alias SantoApi.Bench
  alias SantoApi.Owners
  alias SantoApi.Owners.Stewardship
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo
  alias SantoApiWeb.MCP.Tools

  setup do
    operator = operator_fixture()
    user = user_fixture()
    {:ok, first_vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, second_vehicle} = Registry.ingest("WP0CA298X5L001256")
    {:ok, first_stewardship} = Owners.grant_stewardship(user, first_vehicle)
    {:ok, second_stewardship} = Owners.grant_stewardship(user, second_vehicle)

    %{
      operator: operator,
      operator_scope: Scope.for_user(operator),
      user: user,
      user_scope: Scope.for_user(user),
      first_vehicle: first_vehicle,
      second_vehicle: second_vehicle,
      first_stewardship: first_stewardship,
      second_stewardship: second_stewardship
    }
  end

  test "an operator finds the credential, public Party, and active cars by email or handle",
       ctx do
    assert {:ok, by_email} = Bench.find_access_account(ctx.operator_scope, ctx.user.email)
    assert by_email.user.id == ctx.user.id
    assert by_email.party.id == Owners.party(ctx.user).id
    assert by_email.party.name == ctx.user.handle
    assert by_email.access_decisions == []

    assert MapSet.new(by_email.active_stewardships, & &1.id) ==
             MapSet.new([ctx.first_stewardship.id, ctx.second_stewardship.id])

    assert {:ok, by_handle} = Bench.find_access_account(ctx.operator_scope, ctx.user.handle)
    assert by_handle.user.id == ctx.user.id
    assert {:ok, nil} = Bench.find_access_account(ctx.operator_scope, "absent@example.com")
    assert {:error, :query_required} = Bench.find_access_account(ctx.operator_scope, "  ")
  end

  test "suspension and restoration retain Party, ledger history, and car authority", ctx do
    assert {:ok, entry} =
             Owners.compose_entry(ctx.user_scope, ctx.first_vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "History stays put"}}]
             })

    [claim] = entry.claims
    party_id = Owners.party(ctx.user).id

    assert {:ok, suspended} =
             Bench.suspend_account(
               ctx.operator_scope,
               ctx.user.id,
               0,
               "Credential may be compromised."
             )

    assert suspended.user.suspended_at
    assert suspended.user.access_version == 1
    assert suspended.decision.action == :suspended
    assert suspended.decision.reason == "Credential may be compromised."
    assert suspended.decision.decided_by_user_id == ctx.operator.id
    assert suspended.decision.decided_at

    assert Repo.get!(User, ctx.user.id).party_id == party_id
    assert Repo.get!(Claim, claim.id).asserted_by_party_id == party_id
    assert Owners.party(ctx.user).id == party_id
    assert Repo.get!(Stewardship, ctx.first_stewardship.id).status == :active
    assert Repo.get!(Stewardship, ctx.second_stewardship.id).status == :active

    assert {:ok, restored} =
             Bench.restore_account(
               ctx.operator_scope,
               ctx.user.id,
               1,
               "Account holder completed recovery."
             )

    refute restored.user.suspended_at
    assert restored.user.access_version == 2
    assert restored.decision.action == :restored
    assert restored.decision.reason == "Account holder completed recovery."
    assert restored.decision.decided_by_user_id == ctx.operator.id
    assert restored.decision.decided_at

    assert Repo.get!(Stewardship, ctx.first_stewardship.id).status == :active
    assert Repo.get!(Stewardship, ctx.second_stewardship.id).status == :active

    decisions =
      Repo.all(
        from(d in AccessDecision,
          where: d.user_id == ^ctx.user.id,
          order_by: [asc: d.access_version]
        )
      )

    assert Enum.map(decisions, &{&1.action, &1.access_version}) == [suspended: 1, restored: 2]
    assert Enum.all?(decisions, &(&1.decided_by_user_id == ctx.operator.id))
  end

  test "stale and concurrent opposite account decisions are inert after one transition", ctx do
    assert {:ok, _suspended} =
             Bench.suspend_account(ctx.operator_scope, ctx.user.id, 0, "Investigating access.")

    decisions = [
      {:restore, "Review cleared the account."},
      {:suspend, "Keep the account suspended."}
    ]

    results =
      decisions
      |> Task.async_stream(
        fn
          {:restore, reason} ->
            Bench.restore_account(ctx.operator_scope, ctx.user.id, 1, reason)

          {:suspend, reason} ->
            Bench.suspend_account(ctx.operator_scope, ctx.user.id, 1, reason)
        end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1

    current = Repo.get!(User, ctx.user.id)
    refute current.suspended_at
    assert current.access_version == 2

    assert {:error, {:stale_access_state, 2}} =
             Bench.suspend_account(
               ctx.operator_scope,
               ctx.user.id,
               0,
               "An old active browser must not re-suspend after restoration."
             )

    assert Repo.aggregate(
             from(d in AccessDecision, where: d.user_id == ^ctx.user.id),
             :count
           ) == 2
  end

  test "revoking one car removes owner and MCP authority but retains the other car and history",
       ctx do
    assert {:ok, entry} =
             Owners.compose_entry(ctx.user_scope, ctx.first_vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "Attributed forever"}}]
             })

    [historical_claim] = entry.claims
    party_id = Owners.party(ctx.user).id

    results =
      ["General stewardship review.", "Stale duplicate decision."]
      |> Task.async_stream(
        &Bench.revoke_stewardship(ctx.operator_scope, ctx.first_stewardship.id, &1),
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, %Stewardship{}}, &1)) == 1
    assert Enum.count(results, &match?({:error, :not_active}, &1)) == 1

    revoked = Repo.get!(Stewardship, ctx.first_stewardship.id)
    assert revoked.status == :revoked
    assert revoked.reason in ["General stewardship review.", "Stale duplicate decision."]
    assert revoked.decided_by_user_id == ctx.operator.id
    assert revoked.decided_at

    refute Owners.stewarding?(ctx.user_scope, ctx.first_vehicle)
    assert Owners.stewarding?(ctx.user_scope, ctx.second_vehicle)
    assert Repo.get!(Stewardship, ctx.second_stewardship.id).status == :active

    assert {:error, :not_stewarded} =
             Owners.compose_entry(ctx.user_scope, ctx.first_vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "Must fail"}}]
             })

    assert {:ok, _entry} =
             Owners.compose_entry(ctx.user_scope, ctx.second_vehicle, %{
               date: ~D[2026-08-11],
               claims: [%{predicate: "event.note", value: %{"text" => "Still authorized"}}]
             })

    assert Repo.get!(Claim, historical_claim.id).asserted_by_party_id == party_id
    assert Enum.any?(Registry.timeline(ctx.first_vehicle.id), &(&1.entry_ref == entry.entry_ref))

    assert {:ok, mcp_result} = Tools.call(ctx.user_scope, "my_vehicles", %{})
    [%{text: text}] = mcp_result.content
    refute text =~ ctx.first_vehicle.public_id
    assert text =~ ctx.second_vehicle.public_id
  end

  test "privileged actions require an active operator and concise reasons", ctx do
    non_operator_scope = Scope.for_user(user_fixture())

    assert {:error, :not_authorized} =
             Bench.find_access_account(non_operator_scope, ctx.user.email)

    assert {:error, :not_authorized} =
             Bench.suspend_account(
               non_operator_scope,
               ctx.user.id,
               0,
               "No operator authority."
             )

    assert {:error, :not_authorized} =
             Bench.revoke_stewardship(
               non_operator_scope,
               ctx.first_stewardship.id,
               "No operator authority."
             )

    assert {:error, :reason_required} =
             Bench.suspend_account(ctx.operator_scope, ctx.user.id, 0, "  ")

    assert {:error, :reason_required} =
             Bench.revoke_stewardship(ctx.operator_scope, ctx.first_stewardship.id, "  ")

    refute Repo.get!(User, ctx.user.id).suspended_at
    assert Repo.get!(Stewardship, ctx.first_stewardship.id).status == :active
  end
end
