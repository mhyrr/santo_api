defmodule SantoApi.EventsTest do
  @moduledoc """
  The shared event coordinate stays generic, while each participation remains
  an ordinary owner update with a stable permalink and conversation subject.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async.
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Events
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "eventdriver"})
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle)

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user)}
  end

  test "creates a generic occurrence, participation, and ordinary update in one save", ctx do
    assert {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, event_attrs())

    assert result.event.public_id
    assert result.event.title == "WDCR 2026 Event 2"
    assert result.event.source_status == :community
    assert result.event.timezone == "America/New_York"
    assert result.event.participant_count == 1

    participation = result.participation
    assert participation.entry_ref == result.entry.entry_ref
    assert participation.tags == ["autocross", "rain"]

    assert Enum.map(participation.details, &{&1.label, &1.value}) == [
             {"Best run", "44.182"},
             {"Instructor", "Sam"},
             {"Camber", "-3.0°"}
           ]

    assert [entry] = Registry.timeline(ctx.vehicle.id)
    assert entry.entry_ref == participation.entry_ref
    assert {:ok, _entry} = Registry.fetch_timeline_entry(ctx.vehicle.id, participation.entry_ref)

    assert [claim] = entry.claims
    assert claim.predicate == "event.outing"
    assert claim.value["kind"] == "other"
    assert claim.value["venue"] == "Summit Point Motorsports Park"
    assert claim.value["summary"] =~ "The cold first run"

    {:ok, refreshed} = Registry.fetch_vehicle(ctx.vehicle.id)
    assert refreshed.current_state == ctx.vehicle.current_state
  end

  test "owner-defined detail text is displayed as entered, not converted into metrics", ctx do
    {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, event_attrs())
    assert {:ok, event} = Events.fetch_public_event(result.event.public_id)
    assert [participation] = event.participations

    assert Enum.map(participation.details, & &1.value) == ["44.182", "Sam", "-3.0°"]
    refute Map.has_key?(participation, :score)
    refute Map.has_key?(participation, :standing)
  end

  test "a labeled link is attached to the participation", ctx do
    attrs =
      event_attrs()
      |> Map.put(:links, [
        %{label: "Course walk video", kind: :video, url: "https://example.com/course-walk"}
      ])

    assert {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, attrs)
    assert [attachment] = result.participation.attachments
    assert attachment.label == "Course walk video"
    assert attachment.kind == :video
    assert attachment.url == "https://example.com/course-walk"
    assert result.event.media_count == 1
  end

  test "source links do not inflate the event's media count", ctx do
    attrs =
      event_attrs()
      |> Map.put(:links, [
        %{label: "Organizer details", kind: :link, url: "https://example.com/event-details"}
      ])

    assert {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, attrs)
    assert result.event.media_count == 0
  end

  test "a bad attachment URL rolls back the occurrence and logbook entry", ctx do
    attrs =
      event_attrs()
      |> Map.put(:links, [%{label: "Bad", kind: :link, url: "javascript:alert(1)"}])

    assert {:error, %Ecto.Changeset{}} =
             Events.create_participation(ctx.scope, ctx.vehicle, attrs)

    assert Registry.timeline(ctx.vehicle.id) == []
    assert Events.search_events("WDCR 2026 Event 2") == []
  end

  test "a private account stays off the shared page but remains visible to its author", ctx do
    attrs = put_in(event_attrs(), [:participation, :visibility], :private)
    assert {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, attrs)

    assert {:ok, event} = Events.fetch_public_event(result.event.public_id)
    assert event.participations == []
    assert event.participant_count == 0

    assert {:error, :not_found} =
             Events.participation_for_entry(nil, ctx.vehicle, result.participation.entry_ref)

    assert {:ok, mine} =
             Events.participation_for_entry(
               ctx.scope,
               ctx.vehicle,
               result.participation.entry_ref
             )

    assert mine.visibility == :private
  end

  test "a second participation by the same car is rejected without adding another update", ctx do
    assert {:ok, first} = Events.create_participation(ctx.scope, ctx.vehicle, event_attrs())

    second = %{event_id: first.event.id, participation: event_attrs().participation}

    assert {:error, %Ecto.Changeset{}} =
             Events.create_participation(ctx.scope, ctx.vehicle, second)

    assert length(Registry.timeline(ctx.vehicle.id)) == 1
  end

  test "a stranger cannot attach a car to an event", ctx do
    stranger_scope = Scope.for_user(user_fixture())

    assert {:error, :not_stewarded} =
             Events.create_participation(stranger_scope, ctx.vehicle, event_attrs())

    assert Registry.timeline(ctx.vehicle.id) == []
  end

  test "invalid nullable input returns changeset errors instead of raising" do
    assert {:error, %Ecto.Changeset{} = changeset} =
             Events.validate_draft(%{
               event: %{title: nil, starts_on: nil, place_text: nil, tags: nil},
               participation: %{journal: nil, tags: nil, details: [%{label: nil, value: nil}]}
             })

    refute changeset.valid?
  end

  defp event_attrs do
    %{
      event: %{
        title: "WDCR 2026 Event 2",
        starts_on: ~D[2026-04-19],
        starts_at: ~T[08:00:00],
        ends_at: ~T[16:30:00],
        timezone: "America/New_York",
        place_text: "Summit Point Motorsports Park",
        description: "A wet spring event shared by the people and cars who were there.",
        tags: ["WDCR", "Autocross"]
      },
      participation: %{
        journal:
          "The cold first run was all patience. We found the front axle after lunch and the car came alive.",
        tags: ["autocross", "rain"],
        details: [
          %{label: "Best run", value: "44.182"},
          %{label: "Instructor", value: "Sam"},
          %{label: "Camber", value: "-3.0°"}
        ],
        visibility: :public
      }
    }
  end
end
