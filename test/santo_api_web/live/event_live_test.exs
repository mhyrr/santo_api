defmodule SantoApiWeb.EventLiveTest do
  @moduledoc """
  The generic composer creates the ordinary update and the shared public event
  page; neither surface introduces a discipline-specific form or comment river.
  """

  # Ingest-heavy: real VINs and shared parties deadlock under async.
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Accounts.Scope
  alias SantoApi.Events
  alias SantoApi.Owners
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)
    %{vehicle: vehicle, scope: Scope.for_user(ctx.user)}
  end

  describe "owner composer" do
    test "is authenticated, car-scoped, generic, and reviewable", ctx do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}/events/new")

      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/events/new")

      assert has_element?(view, "#event-composer-page")
      assert has_element?(view, "#event-composer-form")
      assert has_element?(view, "#event-find")
      assert has_element?(view, "#event-details-editor")
      assert has_element?(view, "#event-attachments-editor")
      assert has_element?(view, "#event_timezone")
      refute has_element?(view, "select[name='event[event_type]']")

      params = composer_params(view)

      view
      |> form("#event-composer-form", event: params)
      |> render_submit(%{"intent" => "review"})

      assert has_element?(view, "#event-review")
      assert has_element?(view, "#event-review-form")
      assert has_element?(view, "#event-review", "America/New_York")
      assert has_element?(view, "#event-review", "Visibility: Public")
    end

    test "one save lands on the update permalink and shared event", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}/events/new")

      view
      |> form("#event-composer-form", event: composer_params(view))
      |> render_submit(%{"intent" => "review"})

      assert {:error, {:redirect, %{to: update_path}}} =
               view
               |> form("#event-review-form")
               |> render_submit(%{"intent" => "save"})

      assert update_path =~ "/v/#{ctx.vehicle.public_id}/updates/"
      assert [entry] = Registry.timeline(ctx.vehicle.id)
      assert update_path == "/v/#{ctx.vehicle.public_id}/updates/#{entry.entry_ref}"

      assert {:ok, participation} =
               Events.participation_for_entry(ctx.scope, ctx.vehicle, entry.entry_ref)

      assert Enum.map(participation.details, &{&1.label, &1.value}) == [
               {"Best run", "44.182"}
             ]

      assert participation.event.title == "WDCR 2026 Event 2"
    end

    test "a signed-in stranger is turned away", ctx do
      stranger_conn =
        build_conn()
        |> log_in_user(SantoApi.AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: to, flash: %{"error" => error}}}} =
               live(stranger_conn, ~p"/v/#{ctx.vehicle.public_id}/events/new")

      assert to == "/v/#{ctx.vehicle.public_id}"
      assert error =~ "maintain"
    end
  end

  describe "shared event and car journal" do
    setup ctx do
      {:ok, result} = Events.create_participation(ctx.scope, ctx.vehicle, context_attrs())
      %{result: result}
    end

    test "is public and renders the four shared-event sections", ctx do
      {:ok, view, _html} =
        live(build_conn(), ~p"/events/#{ctx.result.event.public_id}")

      assert has_element?(view, "#shared-event-page")
      assert has_element?(view, "#shared-event-hero")
      assert has_element?(view, "#event-people-cars")
      assert has_element?(view, "#event-what-happened")
      assert has_element?(view, "#event-media")
      assert has_element?(view, "#event-media a[href='https://example.com/run-6']")
      assert has_element?(view, "#event-about")
      assert has_element?(view, "#event-source-links")

      assert has_element?(
               view,
               "#event-source-links a[href='https://example.com/event-details']"
             )

      refute has_element?(view, "#event-media a[href='https://example.com/event-details']")
      refute has_element?(view, "#event-comments")
      refute has_element?(view, "[data-scoreboard]")
    end

    test "uses the shared rich event card on the car and update pages", ctx do
      {:ok, car, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

      assert has_element?(car, "#event-card-#{ctx.result.participation.id}")
      assert has_element?(car, "[data-event-participation]")

      {:ok, update, _html} =
        live(
          build_conn(),
          ~p"/v/#{ctx.vehicle.public_id}/updates/#{ctx.result.participation.entry_ref}"
        )

      assert has_element?(update, "#event-card-#{ctx.result.participation.id}")
      assert has_element?(update, "#update-conversation")
    end

    test "one first-party photo is reused by the car update and shared event", ctx do
      {:ok, result} =
        Events.create_participation(
          ctx.scope,
          ctx.vehicle,
          Map.put(context_attrs(), :uploads, [
            %{
              path: "priv/demo/media/cayman-autocross-paddock.jpg",
              filename: "cayman-autocross-paddock.jpg",
              mime: "image/jpeg",
              kind: :photo,
              label: "The Cayman in the paddock"
            }
          ])
        )

      [attachment | _rest] = result.participation.attachments

      {:ok, event, _html} = live(build_conn(), ~p"/events/#{result.event.public_id}")
      assert has_element?(event, "#event-media-#{attachment.id} img[srcset]")

      {:ok, car, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
      assert has_element?(car, "#event-card-#{result.participation.id} img[srcset]")

      conn =
        get(
          build_conn(),
          "/events/#{result.event.public_id}/attachments/#{attachment.id}/480"
        )

      assert <<0xFF, 0xD8, _rest::binary>> = response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    end
  end

  defp composer_params(view) do
    [detail_name] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#event-details-editor input[name$='[label]']")
      |> LazyHTML.attribute("name")

    [_, detail_id] = Regex.run(~r/event\[details\]\[([^]]+)\]\[label\]/, detail_name)

    %{
      "event_id" => "",
      "title" => "WDCR 2026 Event 2",
      "starts_on" => "2026-04-19",
      "ends_on" => "",
      "starts_at" => "08:00",
      "ends_at" => "16:30",
      "timezone" => "America/New_York",
      "place_text" => "Summit Point Motorsports Park",
      "description" => "Public accounts from a wet spring event.",
      "event_tags" => "WDCR, autocross",
      "journal" => "The cold first run was all patience. The car came alive after lunch.",
      "participation_tags" => "rain, setup test",
      "details" => %{
        detail_id => %{"label" => "Best run", "value" => "44.182"}
      },
      "links" => %{},
      "visibility" => "public"
    }
  end

  defp context_attrs do
    %{
      event: %{
        title: "WDCR 2026 Event 2",
        starts_on: ~D[2026-04-19],
        place_text: "Summit Point Motorsports Park",
        description: "Public accounts from a wet spring event.",
        tags: ["WDCR", "autocross"]
      },
      participation: %{
        journal: "The car came alive after lunch.",
        tags: ["rain"],
        details: [%{label: "Best run", value: "44.182"}],
        visibility: :public
      },
      links: [
        %{label: "Run 6 · onboard", kind: :video, url: "https://example.com/run-6"},
        %{label: "Organizer details", kind: :link, url: "https://example.com/event-details"}
      ]
    }
  end
end
