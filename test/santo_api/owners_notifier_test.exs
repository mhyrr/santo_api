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
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle, handle: "mhyrr")
    {:ok, _submitted} = Owners.submit_proof(challenge, photo())

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.subject =~ "claim"
      assert email.text_body =~ "2007 Porsche"
    end)
  end

  test "a claim on a maintained car warns the person maintaining it", ctx do
    incumbent = user_fixture()
    {:ok, _stewardship} = Owners.grant_stewardship(incumbent, ctx.vehicle, handle: "mhyrr")
    drain()

    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle, handle: "someone-else")
    {:ok, _submitted} = Owners.submit_proof(challenge, photo())

    # The receipt to the claimant goes first; the alert is the one that matters.
    assert_email_sent(fn email -> assert email.subject =~ "with an operator" end)

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == incumbent.email end)
      assert email.subject =~ "Someone else has claimed"
      assert email.text_body =~ "someone-else"
      assert email.text_body =~ "nothing has changed"
    end)
  end

  test "an approval tells the claimant where to go next", ctx do
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle, handle: "mhyrr")
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
    {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle, handle: "mhyrr")
    {:ok, submitted} = Owners.submit_proof(challenge, photo())
    drain()
    {:ok, _denied} = Owners.deny_challenge(submitted, ctx.operator, "the code was not in frame")

    assert_email_sent(fn email ->
      assert Enum.any?(email.to, fn {_name, address} -> address == ctx.user.email end)
      assert email.text_body =~ "the code was not in frame"
      assert email.text_body =~ "try again"
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
end
