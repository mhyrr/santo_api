defmodule SantoApiWeb.EventEditLiveTest do
  @moduledoc """
  The generic event composer is also the day-two participation editor; shared
  occurrence fields stay outside the form and every save keeps the update URL.
  """

  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Events
  alias SantoApi.Events.EventParticipation
  alias SantoApi.Owners
  alias SantoApi.Registry
  alias SantoApi.Repo

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, stewardship} = Owners.grant_stewardship(ctx.user, vehicle)
    scope = Scope.for_user(ctx.user)

    {:ok, result} =
      Events.create_participation(scope, vehicle, %{
        event: %{
          title: "WDCR 2026 Event 2",
          starts_on: ~D[2026-04-19],
          starts_at: ~T[08:00:00],
          ends_at: ~T[16:30:00],
          timezone: "America/New_York",
          place_text: "Summit Point Motorsports Park",
          description: "Public accounts from a wet spring event.",
          tags: ["WDCR", "autocross"]
        },
        participation: %{
          journal: "The cold first run was all patience. The car came alive after lunch.",
          tags: ["rain", "setup test"],
          details: [
            %{label: "Best run", value: "44.182"},
            %{label: "Class", value: "S2"}
          ],
          visibility: :public
        },
        uploads: [photo_upload()],
        links: [
          %{label: "Run 6 · onboard", kind: :video, url: "https://example.com/run-6"}
        ]
      })

    Map.merge(ctx, %{
      vehicle: vehicle,
      stewardship: stewardship,
      scope: scope,
      result: result
    })
  end

  test "the author opens the saved account in the same generic composer", ctx do
    {:ok, view, _html} = live(ctx.conn, edit_path(ctx))

    assert has_element?(view, "#event-participation-edit-page")
    assert has_element?(view, "#event-participation-edit-form")
    assert has_element?(view, "#event-shared-readonly", "WDCR 2026 Event 2")
    assert has_element?(view, "#event-shared-readonly", "shared across everyone")
    assert has_element?(view, "#event_journal", "The cold first run")
    assert has_element?(view, "#event_participation_tags[value='rain, setup test']")
    assert has_element?(view, "#event-existing-attachments")
    refute has_element?(view, "#event_title")
    refute has_element?(view, "#event_visibility")
    refute has_element?(view, "#event-find-existing")

    assert detail_values(view) == ["44.182", "S2"]
  end

  test "submits journal, tags, ordered details, links, removals, and a new photo", ctx do
    original_id = ctx.result.participation.id
    original_ref = ctx.result.participation.entry_ref
    [photo, link] = ctx.result.participation.attachments

    {:ok, view, _html} = live(ctx.conn, edit_path(ctx))
    [first_detail_id, second_detail_id] = detail_ids(view)
    [new_link_id] = new_link_ids(view)

    view
    |> element("#event-detail-#{first_detail_id}-down")
    |> render_click()

    view
    |> element("#event-existing-attachment-#{link.id}-remove")
    |> render_click()

    upload =
      file_input(view, "#event-participation-edit-form", :attachments, [
        %{
          name: "gt3-touring-summit-point.jpg",
          content: File.read!("priv/demo/media/gt3-touring-summit-point.jpg"),
          type: "image/jpeg"
        }
      ])

    assert render_upload(upload, "gt3-touring-summit-point.jpg")

    params = %{
      "event_id" => ctx.result.event.id,
      "journal" => "We found time in the braking zones and stopped chasing the wet line.",
      "participation_tags" => "wet, development",
      "details" => %{
        first_detail_id => %{"label" => "Best run", "value" => "43.901 +1"},
        second_detail_id => %{"label" => "Class", "value" => "S2"}
      },
      "existing_attachments" => %{
        photo.id => %{
          "id" => photo.id,
          "label" => "The Cayman between wet runs",
          "remove" => "false"
        },
        link.id => %{
          "id" => link.id,
          "remove" => "true"
        }
      },
      "upload_labels" => upload_labels(view, "The GT3 at Summit Point"),
      "links" => %{
        new_link_id => %{
          "url" => "https://example.com/course-map.pdf",
          "label" => "Course map",
          "kind" => "file"
        }
      }
    }

    view
    |> form("#event-participation-edit-form", event: params)
    |> render_submit(%{"intent" => "review"})

    assert has_element?(view, "#event-review", "braking zones")
    assert has_element?(view, "#event-participation-edit-review-form")

    assert {:error, {:redirect, %{to: redirect_path}}} =
             view
             |> form("#event-participation-edit-review-form")
             |> render_submit(%{"intent" => "save"})

    assert redirect_path == "/v/#{ctx.vehicle.public_id}/updates/#{original_ref}"

    updated = Repo.get!(EventParticipation, original_id) |> Repo.preload(attachments: :artifact)
    assert updated.entry_ref == original_ref
    assert updated.journal =~ "braking zones"
    assert updated.tags == ["wet", "development"]

    assert Enum.map(updated.details, &{&1.label, &1.value}) == [
             {"Class", "S2"},
             {"Best run", "43.901 +1"}
           ]

    assert Enum.sort(Enum.map(updated.attachments, & &1.label)) ==
             Enum.sort(["The Cayman between wet runs", "The GT3 at Summit Point", "Course map"])

    assert Repo.aggregate(EventParticipation, :count) == 1
    assert [entry] = Registry.timeline(ctx.vehicle.id)
    assert entry.entry_ref == original_ref
  end

  test "invalid input keeps the owner's entered form state", ctx do
    {:ok, view, _html} = live(ctx.conn, edit_path(ctx))
    [first_detail_id | _rest] = detail_ids(view)

    params = %{
      "event_id" => ctx.result.event.id,
      "journal" => "",
      "participation_tags" => "wet, keep this tag",
      "details" => %{
        first_detail_id => %{"label" => "Best run retained", "value" => ""}
      },
      "existing_attachments" => existing_attachment_params(ctx.result.participation),
      "links" => %{}
    }

    view
    |> form("#event-participation-edit-form", event: params)
    |> render_submit(%{"intent" => "review"})

    assert has_element?(view, "#event-participation-edit-error")
    assert has_element?(view, "#event_participation_tags[value='wet, keep this tag']")

    assert has_element?(
             view,
             "#event_detail_#{first_detail_id}_label[value='Best run retained']"
           )

    refute has_element?(view, "#event-review")
  end

  test "the event card and stable update expose Edit our day only to the author", ctx do
    {:ok, car, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")
    href = edit_path(ctx)

    assert has_element?(car, "#event-edit-#{ctx.result.participation.id}[href='#{href}']")

    {:ok, update, _html} =
      live(
        ctx.conn,
        ~p"/v/#{ctx.vehicle.public_id}/updates/#{ctx.result.participation.entry_ref}"
      )

    assert has_element?(update, "#event-edit-#{ctx.result.participation.id}[href='#{href}']")

    stranger_conn =
      build_conn()
      |> log_in_user(SantoApi.AccountsFixtures.user_fixture(%{handle: "eventreader"}))

    {:ok, public_update, _html} =
      live(
        stranger_conn,
        ~p"/v/#{ctx.vehicle.public_id}/updates/#{ctx.result.participation.entry_ref}"
      )

    refute has_element?(public_update, "#event-edit-#{ctx.result.participation.id}")
  end

  test "anonymous, another user, and a later steward cannot open edit mode", ctx do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), edit_path(ctx))

    stranger_conn =
      build_conn()
      |> log_in_user(SantoApi.AccountsFixtures.user_fixture(%{handle: "notthesteward"}))

    assert {:error, {:redirect, %{to: to}}} = live(stranger_conn, edit_path(ctx))
    assert to == "/v/#{ctx.vehicle.public_id}"

    assert {:ok, _revoked} =
             Owners.revoke_stewardship(ctx.stewardship, "Transferred to the next maintainer")

    later = SantoApi.AccountsFixtures.user_fixture(%{handle: "latereditor"})
    {:ok, _stewardship} = Owners.grant_stewardship(later, ctx.vehicle)
    later_conn = build_conn() |> log_in_user(later)

    assert {:error, {:redirect, %{to: later_to, flash: %{"error" => message}}}} =
             live(later_conn, edit_path(ctx))

    assert later_to == "/v/#{ctx.vehicle.public_id}"
    assert message =~ "not yours"
  end

  test "private event media remains available to its author and hidden from a later steward",
       ctx do
    entry_ref = ctx.result.participation.entry_ref

    assert {:ok, _participation} =
             Events.set_participation_visibility(ctx.scope, ctx.vehicle, entry_ref, :private)

    photo = Enum.find(ctx.result.participation.attachments, &(&1.kind == :photo))
    path = "/events/#{ctx.result.event.public_id}/attachments/#{photo.id}/480"
    [photo_placement] = ctx.result.entry.photos

    car_path =
      "/v/#{ctx.vehicle.public_id}/photos/#{photo_placement.id}/480"

    assert_error_sent 404, fn -> get(build_conn(), path) end
    assert_error_sent 404, fn -> get(build_conn(), car_path) end

    owner_conn = get(ctx.conn, path)
    assert response(owner_conn, 200)
    assert get_resp_header(owner_conn, "cache-control") == ["private, no-store"]
    assert response(get(ctx.conn, car_path), 200)

    assert {:ok, _revoked} =
             Owners.revoke_stewardship(ctx.stewardship, "Transferred to the next maintainer")

    later = SantoApi.AccountsFixtures.user_fixture(%{handle: "latermedia"})
    {:ok, _stewardship} = Owners.grant_stewardship(later, ctx.vehicle)
    later_conn = build_conn() |> log_in_user(later)

    assert_error_sent 404, fn -> get(later_conn, path) end
    assert_error_sent 404, fn -> get(later_conn, car_path) end
    assert response(get(ctx.conn, path), 200)
    assert response(get(ctx.conn, car_path), 200)
  end

  defp edit_path(ctx) do
    "/v/#{ctx.vehicle.public_id}/events/new?entry_ref=#{ctx.result.participation.entry_ref}"
  end

  defp detail_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#event-details-editor input[name$='[label]']")
    |> LazyHTML.attribute("name")
    |> Enum.map(fn name ->
      [_, id] = Regex.run(~r/event\[details\]\[([^]]+)\]\[label\]/, name)
      id
    end)
  end

  defp detail_values(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#event-details-editor input[name$='[value]']")
    |> LazyHTML.attribute("value")
  end

  defp new_link_ids(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#event-attachments-editor input[name$='[url]']")
    |> LazyHTML.attribute("name")
    |> Enum.filter(&String.starts_with?(&1, "event[links]"))
    |> Enum.map(fn name ->
      [_, id] = Regex.run(~r/event\[links\]\[([^]]+)\]\[url\]/, name)
      id
    end)
  end

  defp upload_labels(view, label) do
    [name] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#event-attachments-editor input[name^='event[upload_labels]']")
      |> LazyHTML.attribute("name")

    [_, ref] = Regex.run(~r/event\[upload_labels\]\[([^]]+)\]/, name)
    %{ref => label}
  end

  defp existing_attachment_params(participation) do
    Map.new(participation.attachments, fn attachment ->
      attrs = %{
        "id" => attachment.id,
        "label" => attachment.label,
        "remove" => "false"
      }

      attrs =
        if attachment.artifact_id,
          do: attrs,
          else: Map.merge(attrs, %{"url" => attachment.url, "kind" => to_string(attachment.kind)})

      {attachment.id, attrs}
    end)
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
end
