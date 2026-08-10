defmodule SantoApiWeb.ThemeLiveTest do
  use SantoApiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SantoApi.AccountsFixtures

  test "renders the identity, foundations, shell states, controls, and domain components", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-page")
    assert has_element?(view, "#theme-identity")
    assert has_element?(view, "#theme-swatches .club-swatch", "Signal orange")
    assert has_element?(view, "#theme-topbar-anonymous")
    assert has_element?(view, "#theme-topbar-signed-in")
    assert has_element?(view, "#theme-avatars .club-avatar")
    assert has_element?(view, "#theme-controls #theme-odometer")
    assert has_element?(view, "#theme-car-card")
    assert has_element?(view, "#theme-log-entry")
    assert has_element?(view, "#theme-record-row")
  end

  test "renders the recommended car page hierarchy and corrected single-car intake", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-garage-context", "Adding to")
    assert has_element?(view, "#theme-voice-button[aria-label='Dictate update']")
    refute has_element?(view, "#theme-garage-car")
    refute has_element?(view, "#theme-voice-button", "Speak it")

    assert has_element?(view, "#theme-car-page-study")
    assert has_element?(view, "#theme-car-hero")
    assert has_element?(view, "#theme-owner-story")
    assert has_element?(view, "#theme-recent-media")
    assert has_element?(view, "#theme-journal #theme-owner-update")
    assert has_element?(view, "#theme-journal #theme-record-event")
    assert has_element?(view, "#theme-journal #theme-plan-update")
    assert has_element?(view, "#theme-current-state")
    assert has_element?(view, "#theme-history-provenance")
    assert has_element?(view, "#theme-provenance-verified")
    assert has_element?(view, "#theme-provenance-owner")
    assert has_element?(view, "#theme-provenance-conflict")
  end

  test "renders the event journal card and shared event page without a scoreboard", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-event-journal-card")

    assert has_element?(
             view,
             "#theme-event-journal-card",
             "WDCR 2026 AX Championship Event #2"
           )

    assert has_element?(
             view,
             "#theme-event-journal-card a[href='#theme-event-journal-card']",
             "Our day"
           )

    assert has_element?(
             view,
             "#theme-event-journal-card a[href='#theme-shared-event-study']",
             "View the event"
           )

    assert has_element?(view, "#theme-shared-event-study")
    assert has_element?(view, "#theme-event-hero")
    assert has_element?(view, "#theme-event-people .theme-participation-card")
    assert has_element?(view, "#theme-event-happened")
    assert has_element?(view, "#theme-event-media")
    assert has_element?(view, "#theme-event-about")

    assert has_element?(
             view,
             "#theme-event-about a[href*='motorsportreg.com/events/wdcr-2026-ax-championship-event-2']"
           )

    refute has_element?(view, "#theme-shared-event-study", "Leaderboard")
    refute has_element?(view, "#theme-shared-event-study", "Standings")
  end

  test "renders one generic event composer with details, attachments, visibility, and review", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-event-composer")
    assert has_element?(view, "#theme-event-composer-form")
    assert has_element?(view, "#event_update_event")
    assert has_element?(view, "#event_update_journal")
    assert has_element?(view, "#theme-event-details-editor .theme-detail-row")
    assert has_element?(view, "#event_update_attachment_label")
    assert has_element?(view, "#theme-event-file")
    assert has_element?(view, "#event_update_visibility")
    assert has_element?(view, "#theme-event-composer-review")

    refute has_element?(
             view,
             "#theme-event-composer-form select[name='event_update[event_type]']"
           )
  end

  test "the live top bar uses the anonymous navigation when signed out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/theme")

    assert has_element?(view, "#theme-topbar a[href='/users/log-in']", "Sign in")
    assert has_element?(view, "#theme-topbar a[href='/start']", "Add a car")
    refute has_element?(view, "#theme-topbar .club-avatar-menu")
  end

  test "the live top bar uses the handle avatar when signed in", %{conn: conn} do
    user = user_fixture(%{handle: "grolsen"})

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/theme")

    assert has_element?(view, "#theme-topbar .club-avatar-menu")
    assert has_element?(view, "#theme-topbar .club-avatar[title='grolsen']", "G")
    assert has_element?(view, "#theme-topbar a[href='/users/settings']", "Settings")
    refute has_element?(view, "#theme-topbar a[href='/users/log-in']")
  end
end
