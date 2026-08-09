defmodule SantoApiWeb.ClaimTest do
  @moduledoc """
  Claiming a car, from the owner's side (owner_surface §4).

  What these tests hold to: the code is shown once it exists and can be read off
  the screen onto paper, and nothing in the flow promises the claimant anything
  an operator has not decided yet. The handle rides the registration
  reservation (§9.1) — the flow's handle step exists only for accounts that
  predate it.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Owners.Challenge
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    %{vehicle: vehicle, operator: operator_fixture()}
  end

  describe "access" do
    test "anonymous visitors are sent to log in", ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/claim")
    end

    test "an unknown car is a 404", ctx do
      assert_raise SantoApiWeb.VehicleNotFound, fn ->
        live(ctx.conn, ~p"/v/nosuchcar/claim")
      end
    end

    test "the steward of the car has nothing to claim", ctx do
      {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, ctx.vehicle)

      assert {:error, {:redirect, %{to: to}}} =
               live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      assert to == "/v/#{ctx.vehicle.public_id}"
    end
  end

  describe "the code" do
    test "the reserved handle means no handle step (§9.1)", ctx do
      {:ok, view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      refute has_element?(view, "#claim_handle")
      assert html =~ ctx.user.handle
    end

    test "a legacy account is asked for a handle, told plainly it is permanent", ctx do
      conn = log_in_user(build_conn(), legacy_user_fixture())

      {:ok, view, html} = live(conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      assert has_element?(view, "#claim_handle")
      assert html =~ "permanent"
    end

    test "issuing shows the code, spaced for copying onto paper", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      html = view |> form("#claim-form") |> render_submit()

      challenge = Owners.challenge(ctx.user, ctx.vehicle)
      assert challenge.handle == ctx.user.handle
      assert html =~ Challenge.spaced(challenge.code)
      assert html =~ "72 hours"
    end

    test "a handle somebody holds is refused before a legacy account gets a code", ctx do
      {:ok, _party} = Owners.ensure_party(user_fixture(%{handle: "mhyrr"}), "mhyrr")
      legacy = legacy_user_fixture()
      conn = log_in_user(build_conn(), legacy)

      {:ok, view, _html} = live(conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      html = view |> form("#claim-form", %{claim: %{handle: "mhyrr"}}) |> render_submit()

      assert html =~ "already taken"
      assert Owners.challenge(legacy, ctx.vehicle) == nil
    end

    test "a claimant with a minted party is not asked either", ctx do
      {:ok, _party} = Owners.ensure_party(ctx.user, ctx.user.handle)

      {:ok, view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      refute has_element?(view, "#claim_handle")
      assert html =~ ctx.user.handle
    end

    test "a car somebody else maintains says an operator will decide it", ctx do
      incumbent = user_fixture()
      {:ok, _stewardship} = Owners.grant_stewardship(incumbent, ctx.vehicle)

      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      assert html =~ incumbent.handle
      assert html =~ "operator"
    end
  end

  describe "the photo" do
    setup ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      %{challenge: challenge}
    end

    test "uploading the proof hands the claim to an operator", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      upload =
        file_input(view, "#proof-form", :proof, [
          %{name: "vin-plate.jpg", content: "a vin plate and a code", type: "image/jpeg"}
        ])

      assert render_upload(upload, "vin-plate.jpg") =~ "100"

      html = view |> form("#proof-form") |> render_submit()

      assert html =~ "with an operator"
      assert Owners.challenge(ctx.user, ctx.vehicle).status == :submitted
      assert length(Owners.list_pending_challenges()) == 1
    end

    test "submitting without a photo says so rather than sending an empty claim", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      html = view |> form("#proof-form") |> render_submit()

      assert html =~ "photo"
      assert Owners.challenge(ctx.user, ctx.vehicle).status == :issued
    end
  end

  describe "the decision" do
    test "an approved claimant lands in the back-fill moment, not on a bare page", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())
      {:ok, _stewardship} = Owners.approve_challenge(submitted, ctx.operator)

      assert {:error, {:redirect, %{to: to, flash: %{"info" => info}}}} =
               live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      assert to == "/v/#{ctx.vehicle.public_id}/spec"
      assert info =~ "yours to maintain"
    end

    test "a denied claimant is told why and can start again", ctx do
      {:ok, challenge} = Owners.issue_challenge(ctx.user, ctx.vehicle)
      {:ok, submitted} = Owners.submit_proof(challenge, photo())
      {:ok, _denied} = Owners.deny_challenge(submitted, ctx.operator, "the code was not in frame")

      {:ok, view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/claim")

      assert html =~ "the code was not in frame"

      # Their handle was minted with the proof photo and is theirs for good, so
      # starting again does not ask for it a second time.
      refute has_element?(view, "#claim_handle")

      view |> form("#claim-form") |> render_submit()

      assert Owners.challenge(ctx.user, ctx.vehicle).status == :issued
    end
  end

  describe "the public page's invitation" do
    test "an unclaimed car asks the signed-in visitor whether it is theirs", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "This is my car"
      assert html =~ "/v/#{ctx.vehicle.public_id}/claim"
    end

    test "an anonymous visitor is invited to sign in rather than shown a dead link", ctx do
      {:ok, _view, html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "Is this your car?"
      assert html =~ "/users/log-in"
    end

    test "the steward is offered the log, not the claim", ctx do
      {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, ctx.vehicle)

      {:ok, _view, html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

      assert html =~ "Log an update"
      refute html =~ "This is my car"
    end
  end

  defp photo do
    path = Path.join(System.tmp_dir!(), "proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "vin plate #{System.unique_integer()}")
    %{path: path, filename: Path.basename(path), mime: "image/jpeg"}
  end
end
