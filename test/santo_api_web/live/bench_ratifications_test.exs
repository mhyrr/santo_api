defmodule SantoApiWeb.BenchRatificationsTest do
  @moduledoc """
  The production operator control loop for owner-proposed core-car facts.
  """

  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo
  alias SantoApiWeb.MCP.Tools

  setup :register_and_log_in_operator

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    owner = user_fixture(%{handle: unique_user_handle()})
    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    Map.merge(ctx, %{
      vehicle: vehicle,
      owner: owner,
      owner_scope: Scope.for_user(owner),
      owner_party: Owners.party(owner)
    })
  end

  describe "access" do
    test "anonymous visitors are sent to login", _ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/bench/ratifications")
    end

    test "authenticated non-operators are rejected", _ctx do
      conn = log_in_user(build_conn(), user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/bench/ratifications")
    end
  end

  describe "queue" do
    test "an MCP owner factory claim appears with decision context", ctx do
      assert {:ok, result} =
               Tools.call(ctx.owner_scope, "log_entry", %{
                 "vehicle" => ctx.vehicle.public_id,
                 "date" => "2026-08-11",
                 "claims" => [
                   %{
                     "predicate" => "build.paint_code",
                     "value" => %{"code" => "226", "label" => "Linden Green"}
                   }
                 ]
               })

      refute Map.get(result, :isError)
      claim = owner_claim(ctx.vehicle, "build.paint_code", ctx.owner_party.id)

      assert {:ok, competitor} =
               Registry.propose_claim(ctx.vehicle, %{
                 predicate: "build.paint_code",
                 value: %{"code" => "59", "label" => "Slate Grey Metallic"}
               })

      assert {:ok, _admitted} = Registry.ratify_claim(competitor.id)

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      assert has_element?(view, "#ratification-queue")
      assert has_element?(view, "#ratification-count", "1")
      assert has_element?(view, "#ratification-#{claim.id}[data-predicate='build.paint_code']")
      assert has_element?(view, "#ratification-claim-#{claim.id}", "Linden Green")
      assert has_element?(view, "#ratification-method-#{claim.id}", "mcp")
      assert has_element?(view, "#ratification-source-#{claim.id}", claim.entry_ref)
      assert has_element?(view, "#ratification-evidence-#{claim.id}", "owner assertion")
      assert has_element?(view, "#ratification-competitor-#{claim.id}-#{competitor.id}")
      assert has_element?(view, "a[href='/bench/vehicles/#{ctx.vehicle.id}#vehicle-claims']")
      assert has_element?(view, "#ratify-form-#{claim.id}")
      assert has_element?(view, "#reject-form-#{claim.id}")
    end

    test "ordinary owner observations and Vin Santo proposals do not appear", ctx do
      assert {:ok, _ordinary} =
               Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
                 date: ~D[2026-08-11],
                 claims: [
                   %{predicate: "event.note", value: %{"text" => "Drove it to work"}},
                   %{predicate: "observation.mileage", value: 41_720}
                 ]
               })

      assert {:ok, unrelated} =
               Registry.propose_claim(ctx.vehicle, %{
                 predicate: "build.variant",
                 value: "coupe"
               })

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      assert has_element?(view, "#ratification-empty")
      assert has_element?(view, "#ratification-count", "0")
      refute has_element?(view, "#ratification-#{unrelated.id}")
    end

    test "the empty queue exposes its count on the bench front page", ctx do
      {:ok, queue, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(queue)

      assert has_element?(queue, "#ratification-empty")
      assert has_element?(queue, "#ratification-count", "0")

      {:ok, bench, _html} = live(ctx.conn, ~p"/bench")
      render_async(bench)

      assert has_element?(bench, "#ratification-queue-link a[href='/bench/ratifications']")
      assert has_element?(bench, "#ratification-queue-link", "No owner facts waiting")
    end
  end

  describe "decisions" do
    test "ratification admits, audits, recomputes facts, and removes the streamed row", ctx do
      claim = owner_factory_claim(ctx, "build.paint_code", paint("226", "Linden Green"))
      source_entry_ref = claim.entry_ref
      source_party_id = claim.asserted_by_party_id

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      view |> form("#ratify-form-#{claim.id}") |> render_submit()

      refute has_element?(view, "#ratification-#{claim.id}")
      assert has_element?(view, "#ratification-count", "0")
      assert has_element?(view, "#ratification-empty")
      assert has_element?(view, "#ratification-success[data-decision='ratify']")

      decided = Repo.get!(Claim, claim.id)
      assert decided.state == :admitted
      assert decided.ratified_by_party_id == Registry.vin_santo_party().id
      assert decided.ratified_at
      assert decided.entry_ref == source_entry_ref
      assert decided.asserted_by_party_id == source_party_id

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      assert vehicle.facts["build.paint_code"]["status"] == "verified"
      assert vehicle.current_state == %{}
      assert Registry.list_adjudications(vehicle.id) == []
    end

    test "rejection preserves history, removes the row, and leaves no derived fact", ctx do
      claim =
        owner_factory_claim(ctx, "provenance.delivery_dealer", %{
          "name" => "Braman Motorcars",
          "location" => "West Palm Beach, FL"
        })

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      view |> form("#reject-form-#{claim.id}") |> render_submit()

      refute has_element?(view, "#ratification-#{claim.id}")
      assert has_element?(view, "#ratification-count", "0")
      assert has_element?(view, "#ratification-success[data-decision='reject']")

      rejected = Repo.get!(Claim, claim.id)
      assert rejected.state == :rejected
      assert rejected.ratified_by_party_id == Registry.vin_santo_party().id
      assert rejected.ratified_at
      assert rejected.content_hash == claim.content_hash
      assert rejected.entry_ref == claim.entry_ref

      {:ok, vehicle} = Registry.fetch_vehicle(ctx.vehicle.id)
      refute Map.has_key?(vehicle.facts, "provenance.delivery_dealer")
    end

    test "stale and repeated submissions do not create or overwrite decisions", ctx do
      first = owner_factory_claim(ctx, "build.plant", "Uusikaupunki")

      {:ok, other_vehicle} = Registry.ingest("WP0CA298X5L001256")
      {:ok, _stewardship} = Owners.grant_stewardship(ctx.owner, other_vehicle)

      assert {:ok, other_entry} =
               Owners.compose_entry(ctx.owner_scope, other_vehicle, %{
                 date: ~D[2026-08-11],
                 claims: [%{predicate: "build.plant", value: "Leipzig"}]
               })

      [other] = other_entry.claims

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      assert {:ok, externally_decided} =
               Bench.ratify_claim(Scope.for_user(ctx.user), first.id)

      decided_at = externally_decided.ratified_at

      view |> form("#reject-form-#{first.id}") |> render_submit()

      refute has_element?(view, "#ratification-#{first.id}")
      assert has_element?(view, "#ratification-#{other.id}")
      assert has_element?(view, "#ratification-count", "1")
      assert has_element?(view, "#ratification-error", "already resolved")

      render_submit(view, "ratify", %{"decision" => %{"claim_id" => first.id}})

      unchanged = Repo.get!(Claim, first.id)
      assert unchanged.state == :admitted
      assert unchanged.ratified_at == decided_at
      assert Repo.get!(Claim, other.id).state == :proposed
      assert Registry.list_adjudications(ctx.vehicle.id) == []
    end

    test "invalid input reports an error and keeps the pending decision controls", ctx do
      claim = owner_factory_claim(ctx, "build.plant", "Uusikaupunki")

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/ratifications")
      render_async(view)

      render_submit(view, "reject", %{
        "decision" => %{"claim_id" => "not-a-claim"}
      })

      assert has_element?(view, "#ratification-error", "not_found")
      assert has_element?(view, "#ratification-#{claim.id}")
      assert has_element?(view, "#reject-form-#{claim.id}")
      assert has_element?(view, "#ratification-count", "1")
      assert Repo.get!(Claim, claim.id).state == :proposed
    end
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

  defp owner_claim(vehicle, predicate, owner_party_id) do
    Registry.list_claims(vehicle.id)
    |> Enum.find(&(&1.predicate == predicate and &1.asserted_by_party_id == owner_party_id))
  end

  defp paint(code, label), do: %{"code" => code, "label" => label}
end
