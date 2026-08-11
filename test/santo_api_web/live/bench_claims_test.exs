defmodule SantoApiWeb.BenchClaimsTest do
  @moduledoc """
  The claiming queue (owner_surface §4 steps 4–5, §9.2).

  A person decides every claim. No model votes, nothing auto-approves — at this
  volume an operator looking at each photo costs minutes a day and buys eyes on
  the flow during exactly the period we are learning what abuse looks like.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async (CLAUDE.md).
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    operator = operator_fixture()

    %{vehicle: vehicle, operator: operator, conn: log_in_user(build_conn(), operator)}
  end

  describe "access" do
    test "an owner is not an operator", _ctx do
      conn = log_in_user(build_conn(), user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/bench/claims")
    end
  end

  describe "the queue" do
    test "shows the car, the claimant, and the code to look for in the photo", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      {:ok, _view, html} = live(ctx.conn, ~p"/bench/claims")

      assert html =~ "mhyrr"
      assert html =~ SantoApi.Owners.Challenge.spaced(claim.code)
      assert html =~ "2007 Porsche"
      assert html =~ "/bench/artifacts/#{claim.proof_artifact_id}"
    end

    test "says when there is nothing waiting", ctx do
      {:ok, _view, html} = live(ctx.conn, ~p"/bench/claims")

      assert html =~ "Nothing waiting"
    end

    test "approving grants the stewardship and clears the row", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/claims")

      html = view |> element("button[phx-value-id='#{claim.id}']", "Approve") |> render_click()

      assert Owners.steward(ctx.vehicle).name == "mhyrr"
      assert html =~ "Nothing waiting"
    end

    test "denying takes a reason and keeps the car unclaimed", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/claims")

      html =
        view
        |> form("#deny-#{claim.id}", %{reason: "the code was not in frame"})
        |> render_submit()

      assert Owners.steward(ctx.vehicle) == nil
      assert html =~ "Nothing waiting"
      assert Owners.challenge(claimant(claim), ctx.vehicle).reason == "the code was not in frame"
    end

    test "a denial without a reason is refused — the claimant is owed one", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/claims")

      html = view |> form("#deny-#{claim.id}", %{reason: "  "}) |> render_submit()

      assert html =~ "Say why"
      assert Owners.challenge(claimant(claim), ctx.vehicle).status == :submitted
    end

    test "a contested claim moves to the dispute queue instead of appearing twice", ctx do
      {:ok, _incumbent} = Owners.grant_stewardship(user_fixture(%{handle: "mhyrr"}), ctx.vehicle)
      claim = submitted_claim(ctx.vehicle, "someone-else")

      {:ok, claims, _html} = live(ctx.conn, ~p"/bench/claims")
      refute has_element?(claims, "#claim-#{claim.id}")

      {:ok, disputes, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(disputes)

      assert has_element?(disputes, "#dispute-#{claim.id}")
      assert has_element?(disputes, "#dispute-incumbent-#{claim.id}", "mhyrr")
      assert Owners.steward(ctx.vehicle).name == "mhyrr"
    end

    test "the bench's front page counts what is waiting", ctx do
      _claim = submitted_claim(ctx.vehicle, "mhyrr")

      {:ok, _view, html} = live(ctx.conn, ~p"/bench")

      assert html =~ "1 claim"
      assert html =~ "/bench/claims"
    end
  end

  describe "the proof photo" do
    test "an operator can look at it", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      conn = get(ctx.conn, ~p"/bench/artifacts/#{claim.proof_artifact_id}")

      assert conn.status == 200
      assert conn.resp_body == "a vin plate and a code"
      assert Plug.Conn.get_resp_header(conn, "content-type") == ["image/jpeg"]
    end

    test "nobody else can — the rights call on serving artifacts is still open", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")

      conn =
        build_conn()
        |> log_in_user(user_fixture())
        |> get(~p"/bench/artifacts/#{claim.proof_artifact_id}")

      assert redirected_to(conn) == "/"
    end

    test "an artifact whose bytes are gone is a 404, not a crash", ctx do
      claim = submitted_claim(ctx.vehicle, "mhyrr")
      artifact = SantoApi.Repo.get!(SantoApi.Registry.Artifact, claim.proof_artifact_id)

      artifact
      |> Ecto.Changeset.change(storage_ref: "not-a-file-we-hold.jpg")
      |> SantoApi.Repo.update!()

      assert_error_sent 404, fn -> get(ctx.conn, ~p"/bench/artifacts/#{artifact.id}") end
    end
  end

  defp submitted_claim(vehicle, handle) do
    user = user_fixture(%{handle: handle})
    {:ok, challenge} = Owners.issue_challenge(user, vehicle)

    path = Path.join(System.tmp_dir!(), "proof-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "a vin plate and a code")

    {:ok, submitted} =
      Owners.submit_proof(challenge, %{
        path: path,
        filename: Path.basename(path),
        mime: "image/jpeg"
      })

    submitted
  end

  defp claimant(challenge), do: SantoApi.Repo.get!(SantoApi.Accounts.User, challenge.user_id)
end
