defmodule SantoApi.OwnersPrivacyTest do
  use SantoApi.DataCase, async: false

  import SantoApi.AccountsFixtures

  alias SantoApi.Accounts.Scope
  alias SantoApi.Owners
  alias SantoApi.Owners.VehiclePhoto
  alias SantoApi.Registry
  alias SantoApi.Registry.Claim
  alias SantoApi.Repo

  setup do
    {:ok, vehicle} = Registry.ingest("WP0AB29827U782968")
    user = user_fixture(%{handle: "privacydriver"})
    {:ok, _stewardship} = Owners.grant_stewardship(user, vehicle)

    %{vehicle: vehicle, user: user, scope: Scope.for_user(user)}
  end

  test "one change moves the entry's claims and photo placements together", ctx do
    {:ok, entry} = compose_entry(ctx)
    [photo] = entry.photos
    assert photo.hero

    assert {:ok, %{claims: 1, photos: 1, visibility: :private}} =
             Owners.set_entry_visibility(ctx.scope, ctx.vehicle, entry.entry_ref, :private)

    assert Repo.get!(Claim, hd(entry.claims).id).visibility == :private
    assert %{visibility: :private, hero: false} = Repo.get!(VehiclePhoto, photo.id)
    assert Owners.timeline(nil, ctx.vehicle) == []
    assert [%{visibility: :private}] = Owners.timeline(ctx.scope, ctx.vehicle)

    assert {:ok, %{claims: 1, photos: 1, visibility: :public}} =
             Owners.set_entry_visibility(ctx.scope, ctx.vehicle, entry.entry_ref, :public)

    assert Repo.get!(Claim, hd(entry.claims).id).visibility == :public
    assert %{visibility: :public, hero: true} = Repo.get!(VehiclePhoto, photo.id)
    assert [%{visibility: :public}] = Owners.timeline(nil, ctx.vehicle)
  end

  test "a later steward neither sees nor changes the previous steward's private entry", ctx do
    {:ok, entry} = compose_entry(ctx)

    {:ok, _hidden} =
      Owners.set_entry_visibility(ctx.scope, ctx.vehicle, entry.entry_ref, :private)

    stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
    {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "car changed hands")

    next_user = user_fixture(%{handle: "nextsteward"})
    {:ok, _stewardship} = Owners.grant_stewardship(next_user, ctx.vehicle)
    next_scope = Scope.for_user(next_user)

    assert Owners.timeline(next_scope, ctx.vehicle) == []

    assert {:error, :entry_not_found} =
             Owners.set_entry_visibility(next_scope, ctx.vehicle, entry.entry_ref, :public)
  end

  test "bulk privacy changes only contributions authored by the current steward", ctx do
    {:ok, previous_entry} = compose_entry(ctx)
    stewardship = Owners.stewardship(ctx.scope, ctx.vehicle)
    {:ok, _revoked} = Owners.revoke_stewardship(stewardship, "car changed hands")

    next_user = user_fixture(%{handle: "bulkdriver"})
    {:ok, _stewardship} = Owners.grant_stewardship(next_user, ctx.vehicle)
    next_scope = Scope.for_user(next_user)

    {:ok, current_entry} =
      Owners.compose_entry(next_scope, ctx.vehicle, %{
        date: ~D[2026-08-10],
        claims: [%{predicate: "event.note", value: %{"text" => "My first drive"}}]
      })

    assert {:ok, %{claims: 1, photos: 0, visibility: :private}} =
             Owners.set_all_entry_visibility(next_scope, ctx.vehicle, :private)

    assert Repo.get!(Claim, hd(previous_entry.claims).id).visibility == :public
    assert Repo.get!(Claim, hd(current_entry.claims).id).visibility == :private

    assert [public_entry] = Owners.timeline(nil, ctx.vehicle)
    assert public_entry.entry_ref == previous_entry.entry_ref
  end

  defp compose_entry(ctx) do
    Owners.compose_entry(ctx.scope, ctx.vehicle, %{
      date: ~D[2026-08-10],
      claims: [%{predicate: "event.note", value: %{"text" => "Morning drive"}}],
      photos: [
        %{
          path: "priv/demo/media/cayman-autocross-paddock.jpg",
          filename: "morning-drive.jpg",
          mime: "image/jpeg",
          alt_text: "The Cayman after a morning drive"
        }
      ]
    })
  end
end
