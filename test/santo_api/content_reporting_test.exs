defmodule SantoApi.ContentReportingTest do
  @moduledoc """
  Broad content moderation changes public presentation without rewriting the
  claim ledger or granting decision power outside the operator Bench.
  """

  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Bench
  alias SantoApi.Events
  alias SantoApi.Events.{EventAttachment, EventParticipation}
  alias SantoApi.Owners
  alias SantoApi.Owners.VehiclePhoto
  alias SantoApi.Registry
  alias SantoApi.Registry.{Claim, Vehicle}
  alias SantoApi.Repo
  alias SantoApi.Social
  alias SantoApi.Social.ContentReport

  setup do
    owner = user_fixture()
    operator = operator_fixture()

    {:ok, vehicle} =
      Registry.register_chassis(
        :porsche,
        :pre_vin,
        "REPORT-#{System.unique_integer([:positive])}"
      )

    {:ok, _stewardship} = Owners.grant_stewardship(owner, vehicle)

    %{
      owner: owner,
      owner_scope: Scope.for_user(owner),
      operator: operator,
      operator_scope: Scope.for_user(operator),
      vehicle: vehicle
    }
  end

  test "one concurrent car decision wins and retains the complete audit trail", ctx do
    {:ok, entry} = compose_entry(ctx)
    [original_claim] = entry.claims
    original_hash = original_claim.content_hash
    original_state = ctx.vehicle.current_state

    reports =
      for reason <- ["abuse", "fraud"] do
        reporter = user_fixture()

        assert {:ok, report} =
                 Social.report_content(
                   Scope.for_user(reporter),
                   ctx.vehicle,
                   :vehicle,
                   nil,
                   %{"reason" => reason, "detail" => "Please review this car."}
                 )

        report
      end

    non_operator = Scope.for_user(user_fixture())
    assert {:error, :not_authorized} = Bench.list_content_reports(non_operator)

    assert {:error, :not_authorized} =
             Bench.decide_content_report(
               non_operator,
               hd(reports).id,
               :hide,
               "No authority"
             )

    results =
      reports
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {report, index} ->
          Bench.decide_content_report(
            ctx.operator_scope,
            report.id,
            :hide,
            "Confirmed public-safety report #{index}."
          )
        end,
        max_concurrency: 2,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :already_decided}, &1)) == 1

    hidden_vehicle = Repo.get!(Vehicle, ctx.vehicle.id)
    assert hidden_vehicle.visibility == :private
    refute Owners.published?(hidden_vehicle)
    assert hidden_vehicle.current_state == original_state

    retained_claim = Repo.get!(Claim, original_claim.id)
    assert retained_claim.content_hash == original_hash
    assert retained_claim.state == :admitted
    assert retained_claim.visibility == :public

    decided = Repo.all(from(r in ContentReport, order_by: r.inserted_at))
    assert Enum.all?(decided, &(&1.status == :actioned))
    assert Enum.all?(decided, &(&1.decided_by_user_id == ctx.operator.id))
    assert Enum.all?(decided, & &1.decided_at)
    assert decided |> Enum.map(& &1.decision_note) |> Enum.uniq() |> length() == 1

    assert {:error, :already_decided} =
             Bench.decide_content_report(
               ctx.operator_scope,
               hd(reports).id,
               :dismiss,
               "A stale browser cannot reverse the result."
             )

    assert {:ok, []} = Bench.list_content_reports(ctx.operator_scope)
  end

  test "hiding updates moves every presentation row and leaves other history public", ctx do
    {:ok, photo_entry} = compose_entry(ctx)
    [photo_claim] = photo_entry.claims
    [photo] = photo_entry.photos

    {:ok, other_entry} =
      Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        claims: [%{predicate: "event.note", value: %{"text" => "Unaffected history"}}]
      })

    reporter = user_fixture()

    assert {:ok, report} =
             Social.report_content(
               Scope.for_user(reporter),
               ctx.vehicle,
               :entry,
               photo_entry.entry_ref,
               %{"reason" => "doxxing", "detail" => "The photo exposes a home address."}
             )

    assert {:ok, %{hidden: %{claims: 1, photos: 1, participations: 0}}} =
             Bench.decide_content_report(
               ctx.operator_scope,
               report.id,
               :hide,
               "Address visible in the uploaded photo."
             )

    assert Repo.get!(Claim, photo_claim.id).visibility == :private
    assert Repo.get!(VehiclePhoto, photo.id).visibility == :private

    assert {:error, :not_found} =
             Owners.fetch_timeline_entry(nil, ctx.vehicle, photo_entry.entry_ref)

    assert {:ok, visible} =
             Owners.fetch_timeline_entry(nil, ctx.vehicle, other_entry.entry_ref)

    assert visible.entry_ref == other_entry.entry_ref
    assert Repo.get!(Vehicle, ctx.vehicle.id).visibility == :public

    assert {:ok, event} =
             Events.create_participation(ctx.owner_scope, ctx.vehicle, event_attrs())

    event_reporter = user_fixture()

    assert {:ok, event_report} =
             Social.report_content(
               Scope.for_user(event_reporter),
               ctx.vehicle,
               :entry,
               event.participation.entry_ref,
               %{"reason" => "abuse"}
             )

    assert {:ok, %{hidden: %{claims: 1, photos: 0, participations: 1}}} =
             Bench.decide_content_report(
               ctx.operator_scope,
               event_report.id,
               :hide,
               "The event account contains targeted abuse."
             )

    assert Repo.get!(EventParticipation, event.participation.id).visibility == :private
    assert Repo.get!(EventAttachment, hd(event.participation.attachments).id)

    assert {:error, :not_found} =
             Events.participation_for_entry(nil, ctx.vehicle, event.participation.entry_ref)

    assert {:error, :not_found} =
             Social.report_content(
               Scope.for_user(user_fixture()),
               ctx.vehicle,
               :entry,
               event.participation.entry_ref,
               %{"reason" => "other"}
             )
  end

  test "a dismissal keeps content public and records operator, reason, and time", ctx do
    {:ok, entry} = compose_entry(ctx)
    reporter = user_fixture()

    {:ok, report} =
      Social.report_content(
        Scope.for_user(reporter),
        ctx.vehicle,
        :entry,
        entry.entry_ref,
        %{"reason" => "other"}
      )

    assert {:error, :reason_required} =
             Bench.decide_content_report(ctx.operator_scope, report.id, :dismiss, " ")

    assert {:ok, dismissed} =
             Bench.decide_content_report(
               ctx.operator_scope,
               report.id,
               :dismiss,
               "The report describes disagreement, not abuse."
             )

    assert dismissed.status == :dismissed
    assert dismissed.decision_note == "The report describes disagreement, not abuse."
    assert dismissed.decided_by_user_id == ctx.operator.id
    assert dismissed.decided_at
    assert {:ok, _entry} = Owners.fetch_timeline_entry(nil, ctx.vehicle, entry.entry_ref)
  end

  test "Bench metrics derive the 30-day entry mix and correction history", ctx do
    {:ok, composer_entry} =
      Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        claims: [%{predicate: "event.note", value: %{"text" => "Composer original"}}]
      })

    {:ok, mcp_entry} =
      Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        method: :llm_extract,
        method_meta: %{"surface" => "mcp"},
        claims: [%{predicate: "event.note", value: %{"text" => "Agent original"}}]
      })

    assert {:ok, _amended} =
             Owners.amend_entry(ctx.owner_scope, ctx.vehicle, composer_entry.entry_ref, %{
               claims: [%{predicate: "event.note", value: %{"text" => "Composer corrected"}}]
             })

    assert {:ok, 1} = Owners.retract_entry(ctx.owner_scope, ctx.vehicle, mcp_entry.entry_ref)

    assert {:ok, metrics} = Bench.metrics(ctx.operator_scope)
    assert metrics.window_days == 30
    assert metrics.active_stewards == 1
    assert metrics.entries == 2
    assert metrics.composer_entries == 1
    assert metrics.mcp_entries == 1
    assert metrics.mcp_share == 50.0
    assert metrics.amended_entries == 1
    assert metrics.deleted_entries == 1
    assert metrics.correction_rate == 100.0
    assert metrics.claims >= 3
    assert metrics.claims_per_day > 0

    assert {:error, :not_authorized} = Bench.metrics(Scope.for_user(user_fixture()))
  end

  defp compose_entry(ctx) do
    Owners.compose_entry(ctx.owner_scope, ctx.vehicle, %{
      date: ~D[2026-08-10],
      claims: [%{predicate: "event.note", value: %{"text" => "Morning drive"}}],
      photos: [
        %{
          path: "priv/demo/media/cayman-autocross-paddock.jpg",
          filename: "morning-drive.jpg",
          mime: "image/jpeg",
          alt_text: "The car after a morning drive"
        }
      ]
    })
  end

  defp event_attrs do
    %{
      event: %{
        title: "Reported event #{System.unique_integer([:positive])}",
        starts_on: ~D[2026-08-10],
        timezone: "America/New_York",
        place_text: "Summit Point Motorsports Park",
        tags: ["autocross"]
      },
      participation: %{
        journal: "A public event account that will be reviewed.",
        tags: ["autocross"],
        visibility: :public
      },
      links: [
        %{label: "Event notes", kind: :link, url: "https://example.com/event-notes"}
      ]
    }
  end
end
