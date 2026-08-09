defmodule SantoApiWeb.BenchCommentsTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Social

  setup do
    owner = SantoApi.AccountsFixtures.user_fixture()
    author = SantoApi.AccountsFixtures.user_fixture()
    reporter = SantoApi.AccountsFixtures.user_fixture()
    operator = SantoApi.AccountsFixtures.operator_fixture()

    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    {:ok, entry} =
      Owners.compose_entry(Scope.for_user(owner), vehicle, %{
        date: ~D[2026-08-09],
        claims: [%{predicate: "event.note", value: %{"text" => "Back from the first drive"}}]
      })

    {:ok, comment} =
      Social.create_comment(Scope.for_user(author), vehicle, entry.entry_ref, %{
        "body" => "A reply that needs an operator."
      })

    {:ok, report} =
      Social.report_comment(Scope.for_user(reporter), comment.id, %{
        "reason" => "harassment",
        "detail" => "Please review the wording."
      })

    %{
      owner: owner,
      operator: operator,
      vehicle: vehicle,
      entry: entry,
      comment: comment,
      report: report
    }
  end

  test "the queue is operator-only", ctx do
    assert {:error, {:redirect, %{to: "/"}}} =
             live(log_in_user(build_conn(), ctx.owner), ~p"/bench/comments")
  end

  test "an operator sees the reported words, car, reporter, and reason", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/comments")

    assert has_element?(view, "#reports-#{ctx.report.id}", "A reply that needs an operator")
    assert has_element?(view, "#reports-#{ctx.report.id}", "HARASSMENT")

    assert has_element?(
             view,
             "a[href='/v/#{ctx.vehicle.public_id}/updates/#{ctx.entry.entry_ref}']"
           )
  end

  test "hiding a reply clears it from the public conversation and the queue", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/comments")

    view
    |> element("button[phx-click='hide_comment'][phx-value-id='#{ctx.report.id}']")
    |> render_click()

    assert has_element?(view, "#reported-replies-empty", "Nothing waiting")
    assert Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref).comments == []
  end

  test "dismissing a report leaves the reply visible", ctx do
    conn = log_in_user(build_conn(), ctx.operator)
    {:ok, view, _html} = live(conn, ~p"/bench/comments")

    view
    |> element("button[phx-click='dismiss_report'][phx-value-id='#{ctx.report.id}']")
    |> render_click()

    assert has_element?(view, "#reported-replies-empty", "Nothing waiting")
    assert Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref).comment_count == 1
  end
end
