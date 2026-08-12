defmodule SantoApiWeb.BenchReportsTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo
  alias SantoApi.Social
  alias SantoApi.Social.ContentReport

  setup do
    owner = SantoApi.AccountsFixtures.user_fixture()
    reporter = SantoApi.AccountsFixtures.user_fixture()
    operator = SantoApi.AccountsFixtures.operator_fixture()

    {:ok, vehicle} =
      Registry.register_chassis(
        :porsche,
        :pre_vin,
        "BENCH-REPORT-#{System.unique_integer([:positive])}"
      )

    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    {:ok, entry} =
      Owners.compose_entry(Scope.for_user(owner), vehicle, %{
        date: ~D[2026-08-11],
        claims: [%{predicate: "event.note", value: %{"text" => "A reported update"}}]
      })

    {:ok, report} =
      Social.report_content(
        Scope.for_user(reporter),
        vehicle,
        :entry,
        entry.entry_ref,
        %{"reason" => "doxxing", "detail" => "The update names a private address."}
      )

    %{
      owner: owner,
      reporter: reporter,
      operator: operator,
      vehicle: vehicle,
      entry: entry,
      report: report
    }
  end

  test "the queue is refused at the router for a non-operator", ctx do
    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(build_conn(), ctx.owner), ~p"/bench/reports")
  end

  test "an operator sees stable queue and metrics IDs", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/reports")

    assert has_element?(view, "#content-reports-page")
    assert has_element?(view, "#content-report-#{ctx.report.id}")
    assert has_element?(view, "#content-report-decision-#{ctx.report.id}")
    assert has_element?(view, "#content-report-hide-#{ctx.report.id}")
    assert has_element?(view, "#content-report-dismiss-#{ctx.report.id}")

    assert has_element?(
             view,
             "a[href='/v/#{ctx.vehicle.public_id}/updates/#{ctx.entry.entry_ref}']"
           )

    {:ok, index, _html} = live(conn, ~p"/bench")
    assert has_element?(index, "#content-report-queue-link")
    assert has_element?(index, "#bench-metrics")
    assert has_element?(index, "#metric-active-stewards")
    assert has_element?(index, "#metric-entry-mix")
    assert has_element?(index, "#metric-correction-rate")
    assert has_element?(index, "#metric-claims-per-day")
  end

  test "hide outcome clears the queue and removes the update from public history", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/reports")

    view
    |> form("#content-report-hide-#{ctx.report.id}", %{
      "decision" => %{"note" => "Confirmed address exposure in the update."}
    })
    |> render_submit()

    assert has_element?(view, "#content-reports-empty")

    assert {:error, :not_found} =
             Owners.fetch_timeline_entry(nil, ctx.vehicle, ctx.entry.entry_ref)

    [claim] = ctx.entry.claims
    assert Repo.get!(Claim, claim.id).visibility == :private

    decision = Repo.get!(ContentReport, ctx.report.id)
    assert decision.status == :actioned
    assert decision.decision_note == "Confirmed address exposure in the update."
    assert decision.decided_by_user_id == ctx.operator.id
    assert decision.decided_at
  end

  test "dismiss outcome clears the queue and leaves the update public", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/reports")

    view
    |> form("#content-report-dismiss-#{ctx.report.id}", %{
      "decision" => %{"note" => "The address is a public event venue."}
    })
    |> render_submit()

    assert has_element?(view, "#content-reports-empty")

    assert {:ok, _entry} =
             Owners.fetch_timeline_entry(nil, ctx.vehicle, ctx.entry.entry_ref)

    decision = Repo.get!(ContentReport, ctx.report.id)
    assert decision.status == :dismissed
    assert decision.decision_note == "The address is a public event venue."
  end
end
