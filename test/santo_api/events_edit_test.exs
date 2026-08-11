defmodule SantoApi.EventsEditTest do
  @moduledoc """
  Day-two event editing changes one author's participation without changing the
  shared occurrence, update identity, conversation subject, or durable car state.
  """

  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Events
  alias SantoApi.Events.{EventAttachment, EventOccurrence, EventParticipation}
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Registry.Artifact
  alias SantoApi.Repo
  alias SantoApi.Social

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "eventeditor"})
    {:ok, stewardship} = Owners.grant_stewardship(user, vehicle)
    scope = Scope.for_user(user)

    {:ok, result} =
      Events.create_participation(scope, vehicle, %{
        event: occurrence_attrs(),
        participation: participation_attrs(),
        uploads: [photo_upload(), file_upload()],
        links: [
          %{label: "Run 6 · onboard", kind: :video, url: "https://example.com/run-6"}
        ]
      })

    %{
      vehicle: vehicle,
      user: user,
      scope: scope,
      stewardship: stewardship,
      result: result
    }
  end

  test "amends the same participation and update while preserving shared and social state", ctx do
    visitor = user_fixture(%{handle: "eventwitness"})
    visitor_scope = Scope.for_user(visitor)
    entry_ref = ctx.result.participation.entry_ref

    assert {:ok, :added} = Social.toggle_like(visitor_scope, ctx.vehicle, entry_ref)

    assert {:ok, _comment} =
             Social.create_comment(visitor_scope, ctx.vehicle, entry_ref, %{
               body: "The rain line looked quicker from the fence."
             })

    assert {:ok, %{visibility: :private}} =
             Events.set_participation_visibility(ctx.scope, ctx.vehicle, entry_ref, :private)

    before_event = Repo.get!(EventOccurrence, ctx.result.event.id)
    before_state = Repo.get!(SantoApi.Registry.Vehicle, ctx.vehicle.id).current_state
    participation_id = ctx.result.participation.id

    [photo, file, link] = ctx.result.participation.attachments
    assert photo.kind == :photo
    assert file.kind == :file
    assert link.kind == :video
    retained_file_artifact_id = file.artifact_id

    attrs = %{
      event: %{
        title: "A title this editor must ignore",
        starts_on: ~D[2030-01-01],
        place_text: "Somewhere else"
      },
      participation: %{
        journal: "We stopped chasing the wet line and found time in the braking zones.",
        tags: ["wet", "development"],
        details: [
          %{label: "Tire pressure", value: "31F / 29R hot"},
          %{label: "Best run", value: "43.901 +1"},
          %{label: "Class", value: "S2"}
        ],
        visibility: :public
      },
      existing_attachments: [
        %{id: photo.id, label: "The Cayman between wet runs", remove: false},
        %{id: file.id, label: file.label, remove: true},
        %{
          id: link.id,
          label: "Run 7 · onboard",
          kind: :video,
          url: "https://example.com/run-7",
          remove: false
        }
      ],
      uploads: [new_photo_upload()],
      links: [
        %{label: "Course map", kind: :file, url: "https://example.com/course-map.pdf"}
      ]
    }

    assert {:ok, updated} = Events.update_participation(ctx.scope, ctx.vehicle, entry_ref, attrs)

    assert updated.id == participation_id
    assert updated.entry_ref == entry_ref
    assert updated.visibility == :private
    assert updated.journal =~ "braking zones"
    assert updated.tags == ["wet", "development"]

    assert Enum.map(updated.details, &{&1.label, &1.value}) == [
             {"Tire pressure", "31F / 29R hot"},
             {"Best run", "43.901 +1"},
             {"Class", "S2"}
           ]

    assert Enum.map(updated.attachments, &{&1.label, &1.kind, &1.url}) == [
             {"The Cayman between wet runs", :photo, nil},
             {"Run 7 · onboard", :video, "https://example.com/run-7"},
             {"The Cayman turning into the wet slalom", :photo, nil},
             {"Course map", :file, "https://example.com/course-map.pdf"}
           ]

    assert Repo.get(Artifact, retained_file_artifact_id)
    refute Repo.get(EventAttachment, file.id)

    assert [entry] = Owners.timeline(ctx.scope, ctx.vehicle)
    assert entry.entry_ref == entry_ref
    assert entry.visibility == :private
    assert length(entry.photos) == 2

    assert [claim] = entry.claims
    assert claim.value["summary"] == updated.journal
    assert claim.value["venue"] == before_event.place_text

    after_event = Repo.get!(EventOccurrence, before_event.id)

    assert Map.take(after_event, occurrence_fields()) ==
             Map.take(before_event, occurrence_fields())

    after_vehicle = Repo.get!(SantoApi.Registry.Vehicle, ctx.vehicle.id)
    assert after_vehicle.current_state == before_state

    conversation = Social.conversation(visitor_scope, ctx.vehicle, entry_ref)
    assert conversation.like_count == 1
    assert conversation.comment_count == 1
    assert [%{body: "The rain line looked quicker from the fence."}] = conversation.comments

    assert Repo.aggregate(EventParticipation, :count) == 1
  end

  test "rejects another participant, a stranger, and a later steward", ctx do
    {:ok, other_vehicle} = Registry.ingest("WP0AC2A97JS176473")
    other_participant = user_fixture(%{handle: "otherparticipant"})
    other_scope = Scope.for_user(other_participant)
    {:ok, _other_stewardship} = Owners.grant_stewardship(other_participant, other_vehicle)

    assert {:ok, _other_result} =
             Events.create_participation(other_scope, other_vehicle, %{
               event_id: ctx.result.event.id,
               participation: %{
                 journal: "The GT3 found a different line through the same wet course.",
                 tags: ["rain"],
                 details: []
               }
             })

    assert {:error, :not_authorized} =
             Events.update_participation(
               other_scope,
               other_vehicle,
               ctx.result.participation.entry_ref,
               edit_attrs()
             )

    stranger = user_fixture(%{handle: "eventstranger"})
    stranger_scope = Scope.for_user(stranger)

    assert {:error, :not_stewarded} =
             Events.update_participation(
               stranger_scope,
               ctx.vehicle,
               ctx.result.participation.entry_ref,
               edit_attrs()
             )

    assert {:ok, _revoked} =
             Owners.revoke_stewardship(ctx.stewardship, "Transferred to the next maintainer")

    later = user_fixture(%{handle: "latersteward"})
    {:ok, _stewardship} = Owners.grant_stewardship(later, ctx.vehicle)

    assert {:error, :not_authorized} =
             Events.update_participation(
               Scope.for_user(later),
               ctx.vehicle,
               ctx.result.participation.entry_ref,
               edit_attrs()
             )

    assert {:error, :authentication_required} =
             Events.participation_for_edit(
               nil,
               ctx.vehicle,
               ctx.result.participation.entry_ref
             )
  end

  test "invalid input returns errors and leaves the saved account untouched", ctx do
    original = Repo.get!(EventParticipation, ctx.result.participation.id)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Events.update_participation(
               ctx.scope,
               ctx.vehicle,
               ctx.result.participation.entry_ref,
               %{
                 participation: %{
                   journal: "",
                   tags: ["still here"],
                   details: [%{label: "Best run", value: ""}]
                 },
                 existing_attachments: [],
                 links: []
               }
             )

    refute changeset.valid?
    unchanged = Repo.get!(EventParticipation, original.id)
    assert unchanged.journal == original.journal
    assert unchanged.tags == original.tags
    assert [entry] = Registry.timeline(ctx.vehicle.id)
    assert entry.entry_ref == original.entry_ref
  end

  defp occurrence_attrs do
    %{
      title: "WDCR 2026 Event 2",
      starts_on: ~D[2026-04-19],
      starts_at: ~T[08:00:00],
      ends_at: ~T[16:30:00],
      timezone: "America/New_York",
      place_text: "Summit Point Motorsports Park",
      description: "Public accounts from a wet spring event.",
      tags: ["WDCR", "autocross"]
    }
  end

  defp participation_attrs do
    %{
      journal: "The cold first run was all patience. The car came alive after lunch.",
      tags: ["rain", "setup test"],
      details: [
        %{label: "Best run", value: "44.182"},
        %{label: "Class", value: "S2"}
      ],
      visibility: :public
    }
  end

  defp edit_attrs do
    %{
      participation: %{
        journal: "This must not be accepted from another steward.",
        tags: ["unauthorized"],
        details: []
      },
      existing_attachments: [],
      links: []
    }
  end

  defp photo_upload do
    %{
      path: "priv/demo/media/cayman-autocross-paddock.jpg",
      filename: "cayman-autocross-paddock.jpg",
      mime: "image/jpeg",
      kind: :photo,
      label: "The Cayman in the paddock"
    }
  end

  defp new_photo_upload do
    %{
      path: "priv/demo/media/gt3-touring-summit-point.jpg",
      filename: "gt3-touring-summit-point.jpg",
      mime: "image/jpeg",
      kind: :photo,
      label: "The Cayman turning into the wet slalom"
    }
  end

  defp file_upload do
    %{
      path: "docs/design/car_page.md",
      filename: "setup-notes.txt",
      mime: "text/plain",
      kind: :file,
      label: "Setup notes"
    }
  end

  defp occurrence_fields do
    [
      :public_id,
      :creator_user_id,
      :title,
      :starts_on,
      :ends_on,
      :starts_at,
      :ends_at,
      :timezone,
      :place_text,
      :description,
      :tags,
      :source_status
    ]
  end
end
