defmodule SantoApiWeb.BenchAccessTest do
  @moduledoc "The operator surface for account access and one-car authority."

  use SantoApiWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts
  alias SantoApi.Accounts.AccessDecision
  alias SantoApi.Owners
  alias SantoApi.Owners.Stewardship
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo

  setup :register_and_log_in_operator

  setup ctx do
    target = user_fixture()
    {:ok, first_vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, second_vehicle} = Registry.ingest("WP0CA298X5L001256")
    {:ok, first_stewardship} = Owners.grant_stewardship(target, first_vehicle)
    {:ok, second_stewardship} = Owners.grant_stewardship(target, second_vehicle)
    target_scope = SantoApi.Accounts.Scope.for_user(target)

    {:ok, entry} =
      Owners.compose_entry(target_scope, first_vehicle, %{
        date: ~D[2026-08-11],
        claims: [%{predicate: "event.note", value: %{"text" => "Historical entry"}}]
      })

    Map.merge(ctx, %{
      target: target,
      target_scope: target_scope,
      first_vehicle: first_vehicle,
      second_vehicle: second_vehicle,
      first_stewardship: first_stewardship,
      second_stewardship: second_stewardship,
      historical_claim: hd(entry.claims)
    })
  end

  describe "access" do
    test "anonymous visitors are sent to login", _ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/bench/access")
    end

    test "authenticated non-operators receive the existing router refusal", _ctx do
      conn = log_in_user(build_conn(), user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/bench/access")
    end
  end

  describe "account lookup" do
    test "shows credential state, public Party, separate controls, active cars, and stable IDs",
         ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/access")

      assert has_element?(view, "#access-search-panel")
      assert has_element?(view, "#access-search-form")
      assert has_element?(view, "#access-query")
      assert has_element?(view, "#access-search-button")
      refute has_element?(view, "#access-account")

      search(view, ctx.target.email)

      assert has_element?(
               view,
               "#access-account[data-user-id='#{ctx.target.id}'][data-state='active']"
             )

      assert has_element?(view, "#access-account-state[data-state='active']")
      assert has_element?(view, "#access-party[data-party-id='#{Owners.party(ctx.target).id}']")
      assert has_element?(view, "#suspend-account-form-#{ctx.target.id}")
      assert has_element?(view, "#suspend-account-reason-#{ctx.target.id}")
      assert has_element?(view, "#suspend-account-#{ctx.target.id}[data-confirm]")
      refute has_element?(view, "#restore-account-form-#{ctx.target.id}")

      assert has_element?(view, "#access-stewardship-count", "2")
      assert has_element?(view, "#access-stewardships[phx-update='stream']")

      for {stewardship, vehicle} <- [
            {ctx.first_stewardship, ctx.first_vehicle},
            {ctx.second_stewardship, ctx.second_vehicle}
          ] do
        assert has_element?(
                 view,
                 "#access-stewardship-#{stewardship.id}[data-vehicle-id='#{vehicle.id}']"
               )

        assert has_element?(view, "#revoke-stewardship-form-#{stewardship.id}")
        assert has_element?(view, "#revoke-stewardship-reason-#{stewardship.id}")
        assert has_element?(view, "#revoke-stewardship-#{stewardship.id}[data-confirm]")
      end

      assert has_element?(view, "#access-decisions[phx-update='stream']")
      assert has_element?(view, "#access-decisions-empty")
    end

    test "the bench front page links to the access surface", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench")

      assert has_element?(view, "#access-control-link a[href='/bench/access']")
    end

    test "an absent exact identity gets an outcome state rather than a blank panel", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/access")

      search(view, "absent@example.com")

      assert has_element?(view, "#access-not-found")
      refute has_element?(view, "#access-account")
    end
  end

  describe "account decisions" do
    test "suspends everywhere, broadcasts session disconnects, audits, and restores independently",
         ctx do
      target_session = Accounts.generate_user_session_token(ctx.target)
      topic = "users_sessions:#{Base.url_encode64(target_session)}"
      SantoApiWeb.Endpoint.subscribe(topic)

      {:ok, view, _html} = live(ctx.conn, ~p"/bench/access")
      search(view, ctx.target.handle)

      view
      |> form("#suspend-account-form-#{ctx.target.id}",
        account_action: %{reason: "Credential may be compromised."}
      )
      |> render_submit()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^topic}
      assert has_element?(view, "#access-success[data-action='suspended']")
      assert has_element?(view, "#access-account[data-state='suspended']")
      assert has_element?(view, "#restore-account-form-#{ctx.target.id}")
      refute has_element?(view, "#suspend-account-form-#{ctx.target.id}")
      assert has_element?(view, "#access-stewardship-count", "2")

      [suspension] = Repo.all(from(d in AccessDecision, where: d.user_id == ^ctx.target.id))
      assert suspension.reason == "Credential may be compromised."
      assert suspension.decided_by_user_id == ctx.user.id
      assert suspension.decided_at

      view
      |> form("#restore-account-form-#{ctx.target.id}",
        account_action: %{reason: "Account holder completed recovery."}
      )
      |> render_submit()

      assert has_element?(view, "#access-success[data-action='restored']")
      assert has_element?(view, "#access-account[data-state='active']")
      assert has_element?(view, "#suspend-account-form-#{ctx.target.id}")
      assert has_element?(view, "#access-decision-#{suspension.id}[data-action='suspended']")

      assert Repo.aggregate(from(d in AccessDecision, where: d.user_id == ^ctx.target.id), :count) ==
               2

      assert Repo.get!(Stewardship, ctx.first_stewardship.id).status == :active
      assert Repo.get!(Stewardship, ctx.second_stewardship.id).status == :active
    end

    test "a stale browser cannot overwrite a newer account decision", ctx do
      {:ok, first, _html} = live(ctx.conn, ~p"/bench/access")
      {:ok, stale, _html} = live(ctx.conn, ~p"/bench/access")
      search(first, ctx.target.email)
      search(stale, ctx.target.email)

      first
      |> form("#suspend-account-form-#{ctx.target.id}",
        account_action: %{reason: "Current operator decision."}
      )
      |> render_submit()

      stale
      |> form("#suspend-account-form-#{ctx.target.id}",
        account_action: %{reason: "Stale operator decision."}
      )
      |> render_submit()

      assert has_element?(stale, "#access-error", "changed after this page loaded")
      assert has_element?(stale, "#access-account[data-state='suspended']")
      assert has_element?(stale, "#restore-account-form-#{ctx.target.id}")

      assert Repo.aggregate(from(d in AccessDecision, where: d.user_id == ^ctx.target.id), :count) ==
               1

      assert Repo.one(
               from(d in AccessDecision, where: d.user_id == ^ctx.target.id, select: d.reason)
             ) ==
               "Current operator decision."
    end

    test "a blank account reason changes nothing", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/access")
      search(view, ctx.target.email)

      render_submit(view, "suspend_account", %{
        "account_action" => %{
          "user_id" => ctx.target.id,
          "expected_version" => "0",
          "reason" => "  "
        }
      })

      assert has_element?(view, "#access-error", "concise account-access reason")
      assert has_element?(view, "#access-account[data-state='active']")
      refute Repo.exists?(from(d in AccessDecision, where: d.user_id == ^ctx.target.id))
    end
  end

  describe "stewardship decisions" do
    test "revokes one row and leaves the other car plus historical attribution intact", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/bench/access")
      search(view, ctx.target.email)

      view
      |> form("#revoke-stewardship-form-#{ctx.first_stewardship.id}",
        stewardship_action: %{reason: "General access review for this car."}
      )
      |> render_submit()

      assert has_element?(view, "#access-success[data-action='stewardship_revoked']")
      refute has_element?(view, "#access-stewardship-#{ctx.first_stewardship.id}")
      assert has_element?(view, "#access-stewardship-#{ctx.second_stewardship.id}")
      assert has_element?(view, "#access-stewardship-count", "1")

      revoked = Repo.get!(Stewardship, ctx.first_stewardship.id)
      assert revoked.status == :revoked
      assert revoked.reason == "General access review for this car."
      assert revoked.decided_by_user_id == ctx.user.id
      assert revoked.decided_at
      assert Repo.get!(Stewardship, ctx.second_stewardship.id).status == :active

      assert Repo.get!(Claim, ctx.historical_claim.id).asserted_by_party_id ==
               Owners.party(ctx.target).id
    end

    test "a stale revocation removes the row without overwriting the first decision", ctx do
      {:ok, first, _html} = live(ctx.conn, ~p"/bench/access")
      {:ok, stale, _html} = live(ctx.conn, ~p"/bench/access")
      search(first, ctx.target.email)
      search(stale, ctx.target.email)

      first
      |> form("#revoke-stewardship-form-#{ctx.first_stewardship.id}",
        stewardship_action: %{reason: "First and final reason."}
      )
      |> render_submit()

      stale
      |> form("#revoke-stewardship-form-#{ctx.first_stewardship.id}",
        stewardship_action: %{reason: "Stale overwrite."}
      )
      |> render_submit()

      assert has_element?(stale, "#access-error", "already revoked")
      refute has_element?(stale, "#access-stewardship-#{ctx.first_stewardship.id}")
      assert Repo.get!(Stewardship, ctx.first_stewardship.id).reason == "First and final reason."
    end
  end

  defp search(view, query) do
    view
    |> form("#access-search-form", search: %{query: query})
    |> render_submit()
  end
end
