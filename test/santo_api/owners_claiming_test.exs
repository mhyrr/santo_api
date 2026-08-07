defmodule SantoApi.OwnersClaimingTest do
  @moduledoc """
  Proof of possession (owner_surface §4): a challenge code, a photo of the VIN
  plate with that code in frame, and an operator who looks at it.

  What these tests hold to: the code is bound to one person and one car and
  expires, a second claimant on a stewarded car escalates instead of quietly
  failing, and nothing about a claim writes to the ledger — a stewardship says
  who maintains the log, never who owns the car.

  Handles ride the reservation made at registration (§9.1, round 5) — the
  claim flow no longer asks for one. The choose-at-issue path survives only
  for accounts that predate the reservation, exercised here through
  `legacy_user_fixture/1`.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    %{vehicle: vehicle, user: user_fixture(), operator: operator_fixture()}
  end

  describe "issue_challenge/3" do
    test "mints a code bound to this person and this car, good for 72 hours", ctx do
      assert {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)

      assert challenge.user_id == ctx.user.id
      assert challenge.vehicle_id == ctx.vehicle.id
      assert challenge.status == :issued

      # §9.1: the handle was settled at registration; the flow never asked.
      assert challenge.handle == ctx.user.handle
      assert String.length(challenge.code) == 8

      # Unambiguous alphabet: nothing a person could read off a photo two ways.
      refute String.match?(challenge.code, ~r/[01OIL]/)

      hours = DateTime.diff(challenge.expires_at, DateTime.utc_now(), :hour)
      assert hours in 71..72
    end

    test "one live challenge per pair — asking again returns the same code", ctx do
      {:ok, first} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, second} = Owners.issue_challenge(ctx.user, ctx.vehicle)

      assert first.id == second.id
      assert first.code == second.code
    end

    test "refuses the car the caller already maintains", ctx do
      {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, ctx.vehicle)

      assert {:error, :already_stewarded} = Owners.issue_challenge(ctx.user, ctx.vehicle)
    end

    test "the reservation is immutable — offering a different handle is refused", ctx do
      assert {:error, :handle_immutable} =
               Owners.issue_challenge(ctx.user, ctx.vehicle, handle: "someone-else")

      assert Owners.challenge(ctx.user, ctx.vehicle) == nil
    end

    test "a legacy account's handle that cannot be granted is refused now, not at the desk",
         ctx do
      legacy = legacy_user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Owners.issue_challenge(legacy, ctx.vehicle, handle: "ab")

      assert Owners.challenge(legacy, ctx.vehicle) == nil
    end

    test "a handle somebody already holds is refused for a legacy account", ctx do
      {:ok, _party} = Owners.ensure_party(user_fixture(%{handle: "mhyrr"}), "mhyrr")

      assert {:error, :handle_taken} =
               Owners.issue_challenge(legacy_user_fixture(), ctx.vehicle, handle: "mhyrr")
    end

    test "a legacy account with no handle anywhere is asked for one", ctx do
      assert {:error, :handle_required} =
               Owners.issue_challenge(legacy_user_fixture(), ctx.vehicle)
    end

    test "a claimant with a minted party keeps its name and need not supply one", ctx do
      {:ok, party} = Owners.ensure_party(ctx.user, ctx.user.handle)

      assert {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      assert challenge.handle == party.name
    end

    test "a second claimant on a stewarded car gets a code — §4 escalates, never refuses", ctx do
      {:ok, _stewardship} = Owners.grant_stewardship(user_fixture(), ctx.vehicle)

      assert {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      assert Owners.contested?(challenge)
    end
  end

  describe "submit_proof/2" do
    test "attaches the photo as the claimant's own artifact and waits for an operator", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)

      assert {:ok, submitted} = Owners.submit_proof(challenge, photo())

      assert submitted.status == :submitted
      artifact = SantoApi.Repo.get!(SantoApi.Registry.Artifact, submitted.proof_artifact_id)
      assert artifact.kind == :photo
      assert artifact.vehicle_id == ctx.vehicle.id

      # The photo is the claimant's evidence, not ours — attributing it to Vin
      # Santo would say the registry supplied it.
      assert artifact.source_party_id == Owners.party(ctx.user).id
      assert Owners.party(ctx.user).name == ctx.user.handle
    end

    test "a proof photo is not public — the rights call has not been made", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())

      artifact = SantoApi.Repo.get!(SantoApi.Registry.Artifact, submitted.proof_artifact_id)
      assert artifact.visibility == :private
    end

    test "writes no claim — a photo of a VIN plate asserts nothing yet", ctx do
      before = Registry.list_claims(ctx.vehicle.id) |> length()
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, _submitted} = Owners.submit_proof(challenge, photo())

      assert Registry.list_claims(ctx.vehicle.id) |> length() == before
    end

    test "an expired code is not proof — the code has to be newer than the photo", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      expired = expire(challenge)

      assert {:error, :expired} = Owners.submit_proof(expired, photo())
    end

    test "an expired challenge is replaced by a fresh code, not reused", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      expired = expire(challenge)

      assert {:ok, fresh} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      refute fresh.id == expired.id
      refute fresh.code == expired.code
      assert SantoApi.Repo.get!(SantoApi.Owners.Challenge, expired.id).status == :expired
    end

    test "a blurry photo can be replaced while the claim is still waiting", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, blurry} = Owners.submit_proof(challenge, photo())

      assert {:ok, better} = Owners.submit_proof(blurry, photo())
      refute better.proof_artifact_id == blurry.proof_artifact_id
      assert length(Owners.list_pending_challenges()) == 1
    end
  end

  describe "approve_challenge/2" do
    test "grants the stewardship, with the proof and the operator attached", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())

      assert {:ok, stewardship} = Owners.approve_challenge(submitted, ctx.operator)

      assert stewardship.user_id == ctx.user.id
      assert stewardship.vehicle_id == ctx.vehicle.id
      assert stewardship.proof_artifact_id == submitted.proof_artifact_id
      assert stewardship.decided_by_user_id == ctx.operator.id

      assert Owners.steward(ctx.vehicle).name == ctx.user.handle
      assert Owners.challenge(ctx.user, ctx.vehicle).status == :approved
    end

    test "refuses a challenge nobody has proved yet", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)

      assert {:error, :no_proof} = Owners.approve_challenge(challenge, ctx.operator)
    end

    test "a contested car escalates: the incumbent stays and the claim stays open", ctx do
      incumbent = user_fixture()
      {:ok, _incumbent} = Owners.grant_stewardship(incumbent, ctx.vehicle)
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())

      assert {:error, :already_stewarded} = Owners.approve_challenge(submitted, ctx.operator)

      assert Owners.steward(ctx.vehicle).name == incumbent.handle
      assert Owners.challenge(ctx.user, ctx.vehicle).status == :submitted
    end

    test "the same car, once the incumbent is revoked, approves normally", ctx do
      incumbent = user_fixture()
      {:ok, stewardship} = Owners.grant_stewardship(incumbent, ctx.vehicle)
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())

      {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "adjudicated", ctx.operator)

      assert {:ok, _granted} = Owners.approve_challenge(submitted, ctx.operator)
      assert Owners.steward(ctx.vehicle).name == ctx.user.handle
    end
  end

  describe "deny_challenge/3" do
    test "records the reason and grants nothing", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())

      assert {:ok, denied} = Owners.deny_challenge(submitted, ctx.operator, "code not in frame")

      assert denied.status == :denied
      assert denied.reason == "code not in frame"
      assert denied.decided_by_user_id == ctx.operator.id
      assert Owners.steward(ctx.vehicle) == nil
    end

    test "a denied claimant may try again with a fresh code", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())
      {:ok, denied} = Owners.deny_challenge(submitted, ctx.operator, "code not in frame")

      assert {:ok, fresh} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      refute fresh.id == denied.id
      assert fresh.status == :issued
    end

    test "refuses to decide a claim twice", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())
      {:ok, denied} = Owners.deny_challenge(submitted, ctx.operator, "code not in frame")

      assert {:error, :not_pending} = Owners.deny_challenge(denied, ctx.operator, "again")
      assert {:error, :not_pending} = Owners.approve_challenge(denied, ctx.operator)
    end
  end

  describe "the operator queue" do
    test "holds submitted claims only, oldest first — the queue is a queue", ctx do
      {:ok, waiting} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(waiting, photo())

      {:ok, other} = Registry.ingest("WP0AC2A97JS176473")
      {:ok, unproven} = Owners.issue_challenge(user_fixture(), other)

      queue = Owners.list_pending_challenges()

      assert Enum.map(queue, & &1.id) == [submitted.id]
      refute Enum.any?(queue, &(&1.id == unproven.id))
      assert hd(queue).vehicle.id == ctx.vehicle.id
      assert hd(queue).user.id == ctx.user.id
    end

    test "an approved claim leaves the queue", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())
      {:ok, _stewardship} = Owners.approve_challenge(submitted, ctx.operator)

      assert Owners.list_pending_challenges() == []
    end
  end

  defp photo do
    path = Path.join(System.tmp_dir!(), "proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "vin plate, and a code written on a receipt #{System.unique_integer()}")
    %{path: path, filename: Path.basename(path), mime: "image/jpeg"}
  end

  # Time travel by moving the row, not the clock: the expiry is a column and
  # this is the only honest way to be on the other side of it in a test.
  defp expire(challenge) do
    challenge
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :hour))
    |> SantoApi.Repo.update!()
  end
end
