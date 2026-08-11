defmodule SantoApi.OwnersNotifierTest do
  @moduledoc """
  What a claim sends, and to whom (owner_surface §4, §9.1).

  Email is the only notification channel in v1, and the counter-claim alert is
  the one that must not be missed: somebody is asking for a car another person
  maintains, and that person gets a say before anything moves.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApi.DataCase, async: false

  import Swoosh.TestAssertions
  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    context = %{vehicle: vehicle, user: user_fixture(), operator: operator_fixture()}

    # Registering a user sends a confirmation mail, and the test adapter delivers
    # into this process's mailbox in order. Clear the fixtures' mail so the
    # assertions below are about claim mail and not about setup.
    drain()
    context
  end

  test "sending the photo confirms it arrived", ctx do
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
    {:ok, _submitted} = Owners.submit_proof(challenge, photo())

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.subject =~ "claim"
      assert email.text_body =~ "2007 Porsche"
    end)
  end

  test "a claim on a maintained car warns the person maintaining it", ctx do
    incumbent = user_fixture()
    {:ok, _stewardship} = Owners.grant_stewardship(incumbent, ctx.vehicle)
    drain()

    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
    {:ok, _submitted} = Owners.submit_proof(challenge, photo())

    # The receipt to the claimant goes first; the alert is the one that matters.
    assert_email_sent(fn email -> assert email.subject =~ "with an operator" end)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == incumbent.email end)
      assert email.subject =~ "Someone else has claimed"
      assert email.text_body =~ ctx.user.handle
      assert email.text_body =~ "nothing has changed"
    end)
  end

  test "an approval tells the claimant where to go next", ctx do
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
    {:ok, submitted} = Owners.submit_proof(challenge, photo())
    drain()
    {:ok, _stewardship} = Owners.approve_challenge(submitted, ctx.operator)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.subject =~ "yours to maintain"
      assert email.text_body =~ "/v/#{ctx.vehicle.public_id}"
    end)
  end

  test "a denial carries the reason it was denied", ctx do
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
    {:ok, submitted} = Owners.submit_proof(challenge, photo())
    drain()
    {:ok, _denied} = Owners.deny_challenge(submitted, ctx.operator, "the code was not in frame")

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.text_body =~ "the code was not in frame"
      assert email.text_body =~ "try again"
    end)
  end

  test "keeping the incumbent reports the same reason to both people", ctx do
    incumbent = user_fixture(%{handle: unique_user_handle()})
    {:ok, incumbent_stewardship} = claim_and_approve(incumbent, ctx.vehicle, ctx.operator)
    {:ok, submitted} = submit_claim(ctx.user, ctx.vehicle)
    drain()

    assert {:ok, %{outcome: :keep_incumbent}} =
             Owners.resolve_dispute(
               submitted.id,
               ctx.operator,
               :keep_incumbent,
               "The incumbent supplied the current registration."
             )

    assert incumbent_stewardship.status == :active

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.subject =~ "not approved"
      assert email.text_body =~ "current registration"
    end)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == incumbent.email end)
      assert email.subject =~ "remain"
      assert email.text_body =~ "current registration"
    end)
  end

  test "a transfer tells the claimant and the former steward what changed", ctx do
    incumbent = user_fixture(%{handle: unique_user_handle()})
    {:ok, _incumbent_stewardship} = claim_and_approve(incumbent, ctx.vehicle, ctx.operator)
    {:ok, submitted} = submit_claim(ctx.user, ctx.vehicle)
    drain()

    assert {:ok, %{outcome: :transfer_to_claimant}} =
             Owners.resolve_dispute(
               submitted.id,
               ctx.operator,
               :transfer_to_claimant,
               "The claimant supplied the signed transfer bill."
             )

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.subject =~ "yours to maintain"
    end)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == incumbent.email end)
      assert email.subject =~ "transferred"
      assert email.text_body =~ "prior entries remain"
      assert email.text_body =~ "signed transfer bill"
    end)
  end

  defp drain do
    receive do
      {:email, _email} -> drain()
    after
      0 -> :ok
    end
  end

  defp photo do
    path = Path.join(System.tmp_dir!(), "proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "vin plate #{System.unique_integer()}")
    %{path: path, filename: Path.basename(path), mime: "image/jpeg"}
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
end
