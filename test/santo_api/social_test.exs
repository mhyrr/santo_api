defmodule SantoApi.SocialTest do
  @moduledoc """
  Conversation stays useful without leaking into the claim ledger: members can
  appreciate and reply to public updates, authors control only their own words,
  and operators — not car maintainers — decide reports.
  """

  use SantoApi.DataCase, async: false

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Social

  import SantoApi.AccountsFixtures

  setup do
    owner = user_fixture()
    member = user_fixture()
    operator = operator_fixture()

    {:ok, vehicle} =
      Registry.register_chassis(
        :porsche,
        :pre_vin,
        "SOCIAL-#{System.unique_integer([:positive])}"
      )

    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    {:ok, entry} =
      Owners.compose_entry(Scope.for_user(owner), vehicle, %{
        date: ~D[2026-08-09],
        claims: [
          %{predicate: "event.note", value: %{"text" => "First drive after service"}}
        ]
      })

    %{
      vehicle: vehicle,
      entry: entry,
      owner_scope: Scope.for_user(owner),
      member: member,
      member_scope: Scope.for_user(member),
      operator_scope: Scope.for_user(operator)
    }
  end

  test "a reaction toggles without changing the record", ctx do
    assert {:ok, :added} =
             Social.toggle_like(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref)

    assert %{like_count: 1, liked?: true} =
             Social.conversation(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref)

    assert Registry.entry_counts()[ctx.vehicle.id] == 1

    assert {:ok, :removed} =
             Social.toggle_like(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref)

    assert %{like_count: 0, liked?: false} =
             Social.conversation(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref)
  end

  test "a reply is public conversation, not a claim", ctx do
    assert {:ok, comment} =
             Social.create_comment(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref, %{
               "body" => "That first drive after a long job is the best one."
             })

    assert comment.author_handle == ctx.member.handle

    assert %{comments: [listed], comment_count: 1} =
             Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref)

    assert listed.id == comment.id
    assert length(Registry.timeline(ctx.vehicle.id)) == 1
    assert length(Registry.list_claims(ctx.vehicle.id)) == 1
  end

  test "a car maintainer cannot remove somebody else's reply", ctx do
    {:ok, comment} =
      Social.create_comment(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref, %{
        "body" => "Keep the old parts."
      })

    assert {:error, :not_authorized} =
             Social.withdraw_comment(ctx.owner_scope, comment.id)

    assert {:ok, withdrawn} = Social.withdraw_comment(ctx.member_scope, comment.id)
    assert withdrawn.status == :withdrawn
    assert Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref).comments == []
  end

  test "reports go to operators, who may hide the reply", ctx do
    {:ok, comment} =
      Social.create_comment(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref, %{
        "body" => "A reply that needs review."
      })

    reporter = user_fixture()
    reporter_scope = Scope.for_user(reporter)

    assert {:ok, report} =
             Social.report_comment(reporter_scope, comment.id, %{"reason" => "spam"})

    assert Social.list_open_reports(ctx.owner_scope) == []
    assert [queued] = Social.list_open_reports(ctx.operator_scope)
    assert queued.id == report.id
    assert queued.comment.body == "A reply that needs review."

    assert {:ok, hidden} =
             Social.hide_reported_comment(ctx.operator_scope, report.id, "Commercial spam")

    assert hidden.status == :hidden
    assert Social.list_open_reports(ctx.operator_scope) == []
    assert Social.conversation(nil, ctx.vehicle, ctx.entry.entry_ref).comments == []
  end

  test "a stale moderation action returns a refusal instead of raising", ctx do
    {:ok, comment} =
      Social.create_comment(ctx.member_scope, ctx.vehicle, ctx.entry.entry_ref, %{
        "body" => "A reply with a report already decided."
      })

    reporter = user_fixture()

    {:ok, report} =
      Social.report_comment(Scope.for_user(reporter), comment.id, %{"reason" => "other"})

    assert {:ok, _report} = Social.dismiss_report(ctx.operator_scope, report.id, "No action")

    assert {:error, :already_decided} =
             Social.hide_reported_comment(ctx.operator_scope, report.id, "Too late")

    assert {:error, :not_found} =
             Social.hide_reported_comment(ctx.operator_scope, Ecto.UUID.generate(), "Missing")
  end

  test "private and missing updates cannot receive social data", ctx do
    {:ok, private_entry} =
      Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
        date: ~D[2026-08-09],
        visibility: :private,
        claims: [%{predicate: "event.note", value: %{"text" => "Private shakedown note"}}]
      })

    assert {:error, :not_found} =
             Social.create_comment(ctx.member_scope, ctx.vehicle, private_entry.entry_ref, %{
               "body" => "I should not be able to see this."
             })

    assert {:error, :not_found} =
             Social.toggle_like(ctx.member_scope, ctx.vehicle, Ecto.UUID.generate())
  end
end
