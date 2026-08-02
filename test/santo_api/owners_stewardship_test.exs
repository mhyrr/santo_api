defmodule SantoApi.OwnersStewardshipTest do
  @moduledoc """
  Stewardship is authorization, not registry truth (owner_surface §4). Granting
  it writes no claim, asserts no ownership, and says only that this person is
  the one maintaining this car's log.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    %{vehicle: vehicle, operator: operator_fixture()}
  end

  describe "grant_stewardship/3" do
    test "mints the party, links the user, and records who decided", ctx do
      user = user_fixture()

      assert {:ok, stewardship} =
               Owners.grant_stewardship(user, ctx.vehicle,
                 handle: "mhyrr",
                 decided_by: ctx.operator
               )

      assert stewardship.status == :active
      assert stewardship.user_id == user.id
      assert stewardship.vehicle_id == ctx.vehicle.id
      assert stewardship.decided_by_user_id == ctx.operator.id
      assert stewardship.decided_at
      assert Owners.party(user).name == "mhyrr"
    end

    test "writes no claim — possession is not title", ctx do
      before = Registry.list_claims(ctx.vehicle.id) |> length()

      {:ok, _stewardship} =
        Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "mhyrr")

      assert Registry.list_claims(ctx.vehicle.id) |> length() == before
    end

    test "is idempotent — re-granting returns the stewardship already held", ctx do
      user = user_fixture()

      assert {:ok, first} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      assert {:ok, second} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      assert first.id == second.id
    end

    test "refuses a car someone else actively stewards — §4 escalates instead", ctx do
      {:ok, _stewardship} = Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "mhyrr")

      assert {:error, :already_stewarded} =
               Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "someone-else")
    end

    test "a bad handle grants nothing", ctx do
      assert {:error, changeset} =
               Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "ab")

      refute changeset.valid?
      assert Owners.steward(ctx.vehicle) == nil
    end

    test "carries the proof artifact that justified it", ctx do
      {:ok, artifact} = proof_artifact(ctx.vehicle)

      {:ok, stewardship} =
        Owners.grant_stewardship(user_fixture(), ctx.vehicle,
          handle: "mhyrr",
          proof_artifact: artifact
        )

      assert stewardship.proof_artifact_id == artifact.id
    end

    test "a user who already has a handle keeps it", ctx do
      user = user_fixture()
      {:ok, _party} = Owners.ensure_party(user, "mhyrr")

      assert {:ok, _stewardship} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      assert Owners.party(user).name == "mhyrr"
    end
  end

  describe "revoke_stewardship/3" do
    test "is a status flip with a reason — the row stays", ctx do
      user = user_fixture()
      {:ok, stewardship} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")

      assert {:ok, revoked} =
               Owners.revoke_stewardship(stewardship, "sold the car", ctx.operator)

      assert revoked.id == stewardship.id
      assert revoked.status == :revoked
      assert revoked.reason == "sold the car"
      assert revoked.decided_by_user_id == ctx.operator.id
      refute Owners.stewarding?(scope(user), ctx.vehicle)
    end

    test "frees the car for the next steward", ctx do
      {:ok, stewardship} = Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "mhyrr")
      {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "sold the car", ctx.operator)

      assert {:ok, _next} =
               Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "next-one")
    end

    test "refuses to revoke twice", ctx do
      {:ok, stewardship} = Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "mhyrr")
      {:ok, revoked} = Owners.revoke_stewardship(stewardship, "sold the car", ctx.operator)

      assert {:error, :not_active} = Owners.revoke_stewardship(revoked, "again", ctx.operator)
    end

    test "entries made under it stay in the ledger, attributed", ctx do
      user = user_fixture()
      {:ok, stewardship} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      party = Owners.party(user)

      {:ok, claim} =
        Registry.propose_claim(ctx.vehicle, party, %{
          "predicate" => "event.note",
          "value" => %{"text" => "logged while stewarding"},
          "scope_date" => "2026-08-02"
        })

      {:ok, _claim} = Registry.ratify_claim(claim.id, party)
      {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "sold the car", ctx.operator)

      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert entry.party == "mhyrr"
    end
  end

  describe "reads" do
    test "steward/1 is the handle a page says it is maintained by", ctx do
      assert Owners.steward(ctx.vehicle) == nil

      {:ok, _stewardship} = Owners.grant_stewardship(user_fixture(), ctx.vehicle, handle: "mhyrr")
      assert Owners.steward(ctx.vehicle).name == "mhyrr"
    end

    test "stewarding?/2 is false for a car the user has no stewardship on", ctx do
      user = user_fixture()
      refute Owners.stewarding?(scope(user), ctx.vehicle)

      {:ok, _stewardship} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      assert Owners.stewarding?(scope(user), ctx.vehicle)
    end

    test "stewarding?/2 is false without a caller at all", ctx do
      refute Owners.stewarding?(nil, ctx.vehicle)
    end

    test "list_stewarded_vehicles/1 is the caller's garage", ctx do
      user = user_fixture()
      assert Owners.list_stewarded_vehicles(scope(user)) == []

      {:ok, _stewardship} = Owners.grant_stewardship(user, ctx.vehicle, handle: "mhyrr")
      assert [vehicle] = Owners.list_stewarded_vehicles(scope(user))
      assert vehicle.id == ctx.vehicle.id
    end
  end

  defp scope(user), do: SantoApi.Accounts.Scope.for_user(user)

  defp proof_artifact(vehicle) do
    path = Path.join(System.tmp_dir!(), "proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "vin plate and a challenge code")

    Registry.create_upload_artifact(%{
      vehicle_id: vehicle.id,
      path: path,
      filename: Path.basename(path),
      mime: "image/jpeg",
      kind: :photo
    })
  end
end
