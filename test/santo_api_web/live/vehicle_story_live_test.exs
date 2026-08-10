defmodule SantoApiWeb.VehicleStoryLiveTest do
  @moduledoc "The car's mutable opening story is curation, never a ledger claim."

  # Ingest-heavy: real VINs and shared parties deadlock under async.
  use SantoApiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias SantoApi.Owners
  alias SantoApi.Owners.Stories
  alias SantoApi.Registry

  setup :register_and_log_in_user

  setup ctx do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    {:ok, _stewardship} = Owners.grant_stewardship(ctx.user, vehicle)
    %{vehicle: vehicle}
  end

  test "the approved showpiece hierarchy is present without a public empty-story nudge", ctx do
    {:ok, public, _html} = live(build_conn(), ~p"/v/#{ctx.vehicle.public_id}")

    assert has_element?(public, "#vehicle-hero")
    assert has_element?(public, "#vehicle-share")
    assert has_element?(public, "#car-page-nav")
    assert has_element?(public, "#vehicle-logbook")
    assert has_element?(public, "#vehicle-current-state")
    assert has_element?(public, "#vehicle-record")
    refute has_element?(public, "#vehicle-owner-story")

    {:ok, owner, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")
    assert has_element?(owner, "#vehicle-owner-story")
    assert has_element?(owner, "#story-form")
  end

  test "the steward can write and revise the story without adding a claim", ctx do
    claim_count = length(Registry.list_claims(ctx.vehicle.id))
    {:ok, view, _html} = live(ctx.conn, ~p"/v/#{ctx.vehicle.public_id}")

    view
    |> form("#story-form",
      story: %{
        tagline: "Bought for the roads, slowly made my own.",
        body: "I looked for a simple analog car I would not be afraid to use."
      }
    )
    |> render_submit()

    assert has_element?(view, "#vehicle-owner-story", "Bought for the roads")
    assert Stories.get_story(ctx.vehicle).author_user_id == ctx.user.id
    assert length(Registry.list_claims(ctx.vehicle.id)) == claim_count

    view
    |> form("#story-form",
      story: %{
        tagline: "Used hard, maintained carefully.",
        body: "The story changed because the car did."
      }
    )
    |> render_submit()

    assert has_element?(view, "#vehicle-owner-story", "Used hard, maintained carefully")
    assert Stories.get_story(ctx.vehicle).tagline == "Used hard, maintained carefully."
  end

  test "a signed-in stranger never receives the story editor", ctx do
    stranger_conn =
      build_conn()
      |> log_in_user(SantoApi.AccountsFixtures.user_fixture())

    {:ok, view, _html} = live(stranger_conn, ~p"/v/#{ctx.vehicle.public_id}")
    refute has_element?(view, "#story-editor")
    refute has_element?(view, "#story-form")
  end
end
