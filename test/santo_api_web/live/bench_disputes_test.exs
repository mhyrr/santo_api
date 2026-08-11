defmodule SantoApiWeb.BenchDisputesTest do
  @moduledoc "The operator control loop for contested stewardship."

  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApi.Owners
  alias SantoApi.Owners.{Challenge, Stewardship}
  alias SantoApi.Registry
  alias SantoApi.Repo

  setup :register_and_log_in_operator

  setup ctx do
    incumbent = user_fixture(%{handle: unique_user_handle()})
    claimant = user_fixture(%{handle: unique_user_handle()})
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, incumbent_stewardship} = claim_and_approve(incumbent, vehicle, ctx.user)
    {:ok, contested} = submit_claim(claimant, vehicle)

    Map.merge(ctx, %{
      incumbent: incumbent,
      incumbent_stewardship: incumbent_stewardship,
      claimant: claimant,
      contested: contested,
      vehicle: vehicle
    })
  end

  describe "access" do
    test "anonymous visitors are sent to login", _ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/bench/disputes")
    end

    test "authenticated non-operators are rejected", _ctx do
      conn = log_in_user(build_conn(), user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/bench/disputes")
    end
  end

  describe "queue" do
    test "shows the vehicle, both people, both proof records, and decision controls", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      assert has_element?(view, "#dispute-queue")
      assert has_element?(view, "#dispute-count", "1")

      assert has_element?(
               view,
               "#dispute-#{ctx.contested.id}[data-vehicle-id='#{ctx.vehicle.id}']"
             )

      assert has_element?(view, "#dispute-state-#{ctx.contested.id}[data-state='contested']")
      assert has_element?(view, "#dispute-incumbent-#{ctx.contested.id}", ctx.incumbent.handle)
      assert has_element?(view, "#dispute-claimant-#{ctx.contested.id}", ctx.claimant.handle)
      assert has_element?(view, "#dispute-incumbent-proof-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-claimant-proof-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-form-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-reason-#{ctx.contested.id}")

      assert has_element?(
               view,
               "#keep-incumbent-#{ctx.contested.id}[name='decision[outcome]'][value='keep_incumbent']"
             )

      assert has_element?(
               view,
               "#transfer-stewardship-#{ctx.contested.id}[name='decision[outcome]'][value='transfer_to_claimant'][data-confirm]"
             )

      assert has_element?(view, "a[href='/bench/vehicles/#{ctx.vehicle.id}']")
      assert has_element?(view, "a[href='/v/#{ctx.vehicle.public_id}']")
    end

    test "a contested challenge has one operational destination", ctx do
      {:ok, disputes, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(disputes)
      assert has_element?(disputes, "#dispute-#{ctx.contested.id}")

      {:ok, claims, _html} = live(ctx.conn, ~p"/bench/claims")
      refute has_element?(claims, "#claim-#{ctx.contested.id}")
    end

    test "the bench front page exposes the dispute count", ctx do
      {:ok, bench, _html} = live(ctx.conn, ~p"/bench")
      render_async(bench)

      assert has_element?(bench, "#dispute-queue-link a[href='/bench/disputes']")
      assert has_element?(bench, "#dispute-queue-link", "1 stewardship dispute")
    end

    test "resolved queues show an empty state and zero count", ctx do
      assert {:ok, _resolution} =
               Bench.resolve_dispute(
                 Scope.for_user(ctx.user),
                 ctx.contested.id,
                 :keep_incumbent,
                 "The incumbent record prevails."
               )

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      assert has_element?(view, "#dispute-empty")
      assert has_element?(view, "#dispute-count", "0")
    end
  end

  describe "decisions" do
    test "keeping the incumbent resolves and removes the streamed row", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      render_submit(view, "resolve", %{
        "decision" => %{
          "challenge_id" => ctx.contested.id,
          "outcome" => "keep_incumbent",
          "reason" => "The incumbent supplied the current registration."
        }
      })

      refute has_element?(view, "#dispute-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-count", "0")
      assert has_element?(view, "#dispute-empty")
      assert has_element?(view, "#dispute-success[data-outcome='keep_incumbent']")

      assert Repo.get!(Challenge, ctx.contested.id).status == :denied
      assert Repo.get!(Stewardship, ctx.incumbent_stewardship.id).status == :active
    end

    test "transferring stewardship resolves and removes the streamed row", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      render_submit(view, "resolve", %{
        "decision" => %{
          "challenge_id" => ctx.contested.id,
          "outcome" => "transfer_to_claimant",
          "reason" => "The claimant supplied the signed transfer bill."
        }
      })

      refute has_element?(view, "#dispute-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-count", "0")
      assert has_element?(view, "#dispute-success[data-outcome='transfer_to_claimant']")

      assert Repo.get!(Stewardship, ctx.incumbent_stewardship.id).status == :revoked
      assert Repo.get!(Challenge, ctx.contested.id).status == :approved
      assert Owners.steward(ctx.vehicle).name == ctx.claimant.handle
    end

    test "a blank reason renders an error without losing the open decision", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      render_submit(view, "resolve", %{
        "decision" => %{
          "challenge_id" => ctx.contested.id,
          "outcome" => "keep_incumbent",
          "reason" => ""
        }
      })

      assert has_element?(view, "#dispute-error", "concise decision reason")
      assert has_element?(view, "#dispute-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-form-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-count", "1")
      assert Repo.get!(Challenge, ctx.contested.id).status == :submitted
    end

    test "a stale page removes only the already-resolved dispute", ctx do
      other_incumbent = user_fixture(%{handle: unique_user_handle()})
      other_claimant = user_fixture(%{handle: unique_user_handle()})
      {:ok, other_vehicle} = Registry.ingest("WP0AC2A97JS176473")
      {:ok, _stewardship} = claim_and_approve(other_incumbent, other_vehicle, ctx.user)
      {:ok, other} = submit_claim(other_claimant, other_vehicle)

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/disputes")
      render_async(view)

      assert {:ok, external} =
               Bench.resolve_dispute(
                 Scope.for_user(ctx.user),
                 ctx.contested.id,
                 :keep_incumbent,
                 "Resolved elsewhere."
               )

      decided_at = external.challenge.decided_at

      render_submit(view, "resolve", %{
        "decision" => %{
          "challenge_id" => ctx.contested.id,
          "outcome" => "transfer_to_claimant",
          "reason" => "Stale attempt"
        }
      })

      refute has_element?(view, "#dispute-#{ctx.contested.id}")
      assert has_element?(view, "#dispute-#{other.id}")
      assert has_element?(view, "#dispute-count", "1")
      assert has_element?(view, "#dispute-error", "already resolved")
      assert Repo.get!(Challenge, ctx.contested.id).decided_at == decided_at
      assert Repo.get!(Challenge, other.id).status == :submitted
    end
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
    path = Path.join(System.tmp_dir!(), "live-dispute-#{System.unique_integer([:positive])}.jpg")
    File.write!(path, "VIN plate and challenge #{System.unique_integer([:positive])}")
    %{path: path, filename: Path.basename(path), mime: "image/jpeg"}
  end
end
