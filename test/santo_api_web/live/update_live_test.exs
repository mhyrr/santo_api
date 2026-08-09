defmodule SantoApiWeb.UpdateLiveTest do
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Social

  setup do
    owner = SantoApi.AccountsFixtures.user_fixture()
    member = SantoApi.AccountsFixtures.user_fixture()
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    {:ok, entry} =
      Owners.compose_entry(Scope.for_user(owner), vehicle, %{
        date: ~D[2026-08-09],
        claims: [
          %{
            predicate: "event.outing",
            value: %{
              "kind" => "drive",
              "summary" => "Dawn run up Angeles Crest",
              "venue" => "Angeles Crest Highway"
            }
          }
        ]
      })

    %{
      owner: owner,
      member: member,
      vehicle: vehicle,
      entry: entry,
      path: ~p"/v/#{vehicle.public_id}/updates/#{entry.entry_ref}"
    }
  end

  test "the car page links each composed update to its share page", ctx do
    {:ok, view, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    assert has_element?(view, "a[href='#{ctx.path}']", "Dawn run")
  end

  test "an update has a stable public page while posting requires sign-in", ctx do
    {:ok, view, _html} = live(build_conn(), ctx.path)

    assert has_element?(view, "#update-card", "Dawn run up Angeles Crest")
    assert has_element?(view, "#update-conversation")
    assert has_element?(view, "a[href='/users/log-in']", "Love this")
    refute has_element?(view, "#update-comment-form")
  end

  test "a member can appreciate and reply without changing the timeline", ctx do
    conn = log_in_user(build_conn(), ctx.member)
    {:ok, view, _html} = live(conn, ctx.path)

    view |> element("#update-like-button") |> render_click()
    assert has_element?(view, "#update-like-button[aria-pressed='true']", "1")

    view
    |> form("#update-comment-form", comment: %{body: "This is exactly the right use for it."})
    |> render_submit()

    assert has_element?(view, "#update-comments article", "@#{ctx.member.handle}")
    assert has_element?(view, "#update-comments article", "exactly the right use")
    assert length(Registry.timeline(ctx.vehicle.id)) == 1
  end

  test "the car's maintainer cannot moderate another member's reply", ctx do
    {:ok, comment} =
      Social.create_comment(Scope.for_user(ctx.member), ctx.vehicle, ctx.entry.entry_ref, %{
        "body" => "Keep driving it."
      })

    conn = log_in_user(build_conn(), ctx.owner)
    {:ok, view, _html} = live(conn, ctx.path)

    refute has_element?(view, "#comment-#{comment.id} button", "Withdraw")
    assert has_element?(view, "#comment-#{comment.id} button", "Report")

    html = render_click(view, "withdraw_comment", %{"id" => comment.id})
    assert html =~ "not yours"
    assert Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref).comment_count == 1
  end

  test "a member can report a reply to operators", ctx do
    another_member = SantoApi.AccountsFixtures.user_fixture()

    {:ok, comment} =
      Social.create_comment(Scope.for_user(another_member), ctx.vehicle, ctx.entry.entry_ref, %{
        "body" => "A reply under review."
      })

    conn = log_in_user(build_conn(), ctx.member)
    {:ok, view, _html} = live(conn, ctx.path)

    view |> element("#comment-#{comment.id} button", "Report") |> render_click()
    assert has_element?(view, "#comment-report-#{comment.id}")

    view
    |> form("#comment-report-#{comment.id}", report: %{reason: "spam", detail: "Commercial link"})
    |> render_submit()

    operator = SantoApi.AccountsFixtures.operator_fixture()
    assert [_report] = Social.list_open_reports(Scope.for_user(operator))
  end

  test "a private update has no share or conversation page", ctx do
    {:ok, private_entry} =
      Owners.compose_entry(Scope.for_user(ctx.owner), ctx.vehicle, %{
        date: ~D[2026-08-09],
        visibility: :private,
        claims: [%{predicate: "event.note", value: %{"text" => "Private note"}}]
      })

    assert_raise SantoApiWeb.VehicleNotFound, fn ->
      live(
        log_in_user(build_conn(), ctx.owner),
        ~p"/v/#{ctx.vehicle.public_id}/updates/#{private_entry.entry_ref}"
      )
    end
  end
end
