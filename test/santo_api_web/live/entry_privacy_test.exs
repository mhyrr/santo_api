defmodule SantoApiWeb.EntryPrivacyTest do
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

  test "the author can take one update off the public page and put it back", ctx do
    {:ok, entry} = note(ctx, "An early morning drive")
    {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")
    control = "#entry-visibility-#{entry.entry_ref}"

    assert has_element?(view, control <> "[phx-value-visibility=private]", "Hide this update")
    view |> element(control) |> render_click()

    assert has_element?(
             view,
             control <> "[phx-value-visibility=public]",
             "Put on the public page"
           )

    assert has_element?(view, "#entry-#{entry.entry_ref}", "Not on the public page")

    {:ok, visitor, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    refute has_element?(visitor, "#entry-#{entry.entry_ref}")

    view |> element(control) |> render_click()
    {:ok, visitor, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    assert has_element?(visitor, "#entry-#{entry.entry_ref}")
  end

  test "the steward-only data panel exposes export and bulk privacy controls", ctx do
    {:ok, first} = note(ctx, "First note")
    {:ok, second} = note(ctx, "Second note", ~D[2026-08-11])
    {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

    assert has_element?(view, "#vehicle-data-controls")

    assert has_element?(
             view,
             "#vehicle-record-export[href='/v/#{ctx.vehicle.public_id}/export']"
           )

    view |> element("#all-entries-private") |> render_click()

    assert has_element?(view, "#entry-#{first.entry_ref}", "Not on the public page")
    assert has_element?(view, "#entry-#{second.entry_ref}", "Not on the public page")

    {:ok, visitor, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    refute has_element?(visitor, "#vehicle-data-controls")
    refute has_element?(visitor, "#entry-#{first.entry_ref}")
    refute has_element?(visitor, "#entry-#{second.entry_ref}")

    view |> element("#all-entries-public") |> render_click()
    {:ok, visitor, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")
    assert has_element?(visitor, "#entry-#{first.entry_ref}")
    assert has_element?(visitor, "#entry-#{second.entry_ref}")
  end

  test "the same control covers an event card and its shared-event account", ctx do
    {:ok, result} =
      Events.create_participation(ctx.scope, ctx.vehicle, %{
        event: %{
          title: "WDCR 2026 Event 2",
          starts_on: ~D[2026-04-19],
          place_text: "Summit Point Motorsports Park"
        },
        participation: %{
          journal: "The front axle finally came alive after lunch.",
          visibility: :public
        }
      })

    {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")
    control = "#entry-visibility-#{result.participation.entry_ref}"

    assert has_element?(view, control, "Hide this update")
    view |> element(control) |> render_click()

    assert has_element?(view, control, "Put on the public page")
    assert {:ok, event} = Events.fetch_public_event(result.event.public_id)
    assert event.participations == []
  end

  defp note(ctx, text, date \\ ~D[2026-08-10]) do
    Owners.compose_entry(ctx.scope, ctx.vehicle, %{
      date: date,
      claims: [%{predicate: "event.note", value: %{"text" => text}}]
    })
  end
end
